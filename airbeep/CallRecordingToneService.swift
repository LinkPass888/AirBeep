import Combine
import Foundation
import UIKit

enum CallRecordingToneError: LocalizedError {
    case unsupported
    case pairingRequired
    case airliftUnavailable
    case airliftFailed(String)
    case toneReadFailed(String, String)
    case missingTone(String)
    case missingBackup
    case invalidToneBundle
    case verificationFailed(String)
    case languageRestoreRequired
    case nothingToBackup
    case backupIncomplete

    var errorDescription: String? {
        switch self {
        case .unsupported:
            String(localized: "This device or system version is not supported.")
        case .pairingRequired:
            String(localized: "Pair this iPhone and connect LocalDevVPN before changing recording tones.")
        case .airliftUnavailable:
            String(localized: "This build is missing AirLift file access support.")
        case .airliftFailed(let reason):
            String(format: String(localized: "AirLift operation failed: %@"), reason)
        case .toneReadFailed(let name, let reason):
            String(format: String(localized: "Could not read %@: %@"), name, reason)
        case .missingTone(let name):
            String(format: String(localized: "Missing system tone: %@"), name)
        case .missingBackup:
            String(localized: "No original tone backup is available.")
        case .invalidToneBundle:
            String(localized: "The bundled silent tones are missing.")
        case .verificationFailed(let name):
            String(format: String(localized: "Could not verify %@ after writing."), name)
        case .languageRestoreRequired:
            String(localized: "The original tones were not backed up before they were replaced. Change the system language once (Settings › General › Language & Region) to force iOS to regenerate the original tones, then reopen AirBeep.")
        case .nothingToBackup:
            String(localized: "The tones on this device are already silent, so there are no originals left to back up. Change the system language once (Settings › General › Language & Region) to force iOS to regenerate them, then try again.")
        case .backupIncomplete:
            String(localized: "Only some of the original tones could be read, so the backup is incomplete. The rest can still be recovered by changing the system language once.")
        }
    }
}

/// Records whether the current silent tones were applied without a complete
/// original backup. The system regenerates the original disclosure tones when
/// the system language changes, so that remains the documented recovery path;
/// this flag only makes the restore flow explain it instead of pretending a
/// backup exists.
private enum ToneBackupStateCache {
    private static let key = "CallRecordingToneSilencedWithoutBackup"

    static func load() -> Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    static func save(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: key)
    }
}

@MainActor
final class CallRecordingToneService: ObservableObject {
    static let shared = CallRecordingToneService()

    /// Whether a complete original-tone backup exists on disk. The home screen
    /// reads this to offer "Back Up Original Tones" when false and "Restore
    /// Original Tones" when true. Refreshing it only reads the Documents folder
    /// — no airlift call — so it is cheap enough to do on every appearance.
    @Published private(set) var backupReady = false
    @Published private(set) var isBusy = false
    @Published private(set) var lastError: String?
    /// Set when an operation finished successfully; the view shows it as an
    /// alert. The current tone state is deliberately not displayed: detecting it
    /// needs a device read, which is unreliable on some iOS releases.
    @Published private(set) var successMessage: String?
    /// Set by the manual tone-status check; the view shows it as an alert.
    /// Reading the tones is only ever done on explicit request because the
    /// read channel is unreliable on some iOS releases.
    @Published private(set) var verificationMessage: String?
    @Published private(set) var needsAirliftSetup = false
    @Published private(set) var busyMessage: String?

    private enum AccessBackend {
        case airlift(pairingPath: String)
    }

    private struct ToneFile {
        let name: String
        let systemPath: String
        let backupName: String
        let resourceName: String
        let resourceExtension: String
        /// Not shipped on every iOS release; a missing or unreadable optional
        /// tone never blocks an operation.
        let optional: Bool
    }

    private let files = [
        ToneFile(
            name: "StartDisclosureWithTone.m4a",
            systemPath: "/var/mobile/Library/CallServices/Greetings/default/StartDisclosureWithTone.m4a",
            backupName: "StartDisclosureWithTone.m4a",
            resourceName: "AirBeepStartSilence",
            resourceExtension: "m4a",
            optional: false
        ),
        ToneFile(
            name: "StartDisclosure.caf",
            systemPath: "/var/mobile/Library/CallServices/Greetings/default/StartDisclosure.caf",
            backupName: "StartDisclosure.caf",
            resourceName: "AirBeepStartSilence",
            resourceExtension: "caf",
            optional: true
        ),
        ToneFile(
            name: "StopDisclosure.caf",
            systemPath: "/var/mobile/Library/CallServices/Greetings/default/StopDisclosure.caf",
            backupName: "StopDisclosure.caf",
            resourceName: "AirBeepStopSilence",
            resourceExtension: "caf",
            optional: false
        )
    ]

    private var backupDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appending(path: "AirBeepBackups", directoryHint: .isDirectory)
    }

    private init() {}

    /// Refreshes what can be known without touching the device.
    ///
    /// The current tone is deliberately *not* detected here: that needs an
    /// airlift read, which is unreliable on some iOS releases and would surface
    /// a spurious error on every launch. Only the backup state is refreshed,
    /// which is a plain Documents folder check.
    func refresh() {
        guard !isBusy else { return }
        refreshBackupState()
        needsAirliftSetup = false
        lastError = nil
        successMessage = nil
        AirBeepLog.shared.append("refresh: backupReady = \(backupReady)")
    }

    func clearError() {
        lastError = nil
    }

    func clearSuccess() {
        successMessage = nil
    }

    func clearVerification() {
        verificationMessage = nil
    }

    /// Reads the current disclosure tones and saves them as the restore source.
    ///
    /// Kept separate from silencing so the backup can be created while the
    /// originals are still intact, and so an incomplete backup is reported here
    /// instead of silently degrading the later restore.
    func backupOriginalTones() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        AirBeepLog.shared.append("backupOriginalTones: start")

        await withBusyScreen(String(localized: "Backing up original call recording tones")) { [self] in
            do {
                NetworkStatus.syncTargetHostsToAirlift()

                let backend = try accessBackend()
                let current = await readTonesTolerant(using: backend)
                let silent = try silentTones()
                // Only conclude "already silent" when at least one tone was
                // actually read: an all-nil table is a read failure, not a
                // silent device, and falls through to the backup check.
                let anyReadable = current.contains { $0 != nil }
                if anyReadable, Self.tones(current, equal: silent, requireAll: false) {
                    // Every readable tone is already the bundled silence, so
                    // there are no originals left to save.
                    throw CallRecordingToneError.nothingToBackup
                }

                try self.ensureBackup(current)
                self.refreshBackupState()
                guard self.backupReady else {
                    // A required tone could not be read. What was read is
                    // already saved; the language-change path still recovers
                    // the rest (see .languageRestoreRequired).
                    throw CallRecordingToneError.backupIncomplete
                }

                self.finishSuccess(
                    String(localized: "The original recording tones were backed up. You can silence them now.")
                )
                AirBeepLog.shared.append("backupOriginalTones: success")
            } catch {
                self.reportOperationError(error)
            }
        }
    }

    func applySilentTone() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        AirBeepLog.shared.append("applySilentTone: start")

        await withBusyScreen(String(localized: "Applying silence to call recording tones")) { [self] in
            do {
                // The interface set may have changed since launch (VPN enabled,
                // Wi-Fi subnet changed) — refresh the tunnel candidates first.
                NetworkStatus.syncTargetHostsToAirlift()

                let backend = try accessBackend()
                let current = await readTonesTolerant(using: backend)
                let silent = try silentTones()
                if Self.tones(current, equal: silent, requireAll: true) {
                    // Already silent. Reported as success without a write, and
                    // without touching ToneBackupStateCache: nothing was
                    // replaced in this run.
                    self.refreshBackupState()
                    self.finishSuccess(
                        String(localized: "The recording tones are already silent.")
                    )
                    AirBeepLog.shared.append("applySilentTone: already silent")
                    return
                }

                try self.ensureBackup(current)
                self.refreshBackupState()
                let haveBackup = self.backupReady
                AirBeepLog.shared.append(
                    "applySilentTone: backup complete=\(haveBackup), writing silence"
                )
                if !haveBackup {
                    // Reading a required tone failed and it was never backed up.
                    // Proceed anyway: iOS regenerates the original disclosure
                    // tones when the system language changes, which stays the
                    // documented recovery path (see restoreSystemTone).
                    AirBeepLog.shared.append(
                        "applySilentTone: no complete backup; language change remains the recovery path"
                    )
                }

                do {
                    let verified = try await self.writeTones(silent, using: backend)
                    ToneBackupStateCache.save(!haveBackup)
                    if verified {
                        self.finishSuccess(
                            haveBackup
                                ? String(localized: "The recording tones were silenced.")
                                : String(localized: "The recording tones were silenced, but the originals could not be fully backed up. Change the system language once to get them back.")
                        )
                    } else {
                        // The write channel reported success but the read-back
                        // could not confirm it (the read channel is unreliable
                        // on some iOS releases). Say so instead of claiming a
                        // verified success, and point at the manual check.
                        self.finishSuccess(
                            String(localized: "The silence was written, but the result could not be verified automatically. Use \"Check tone status\" to confirm.")
                        )
                    }
                    AirBeepLog.shared.append("applySilentTone: success")
                } catch {
                    try? await self.writeTones(current, using: backend)
                    throw error
                }
            } catch {
                self.reportOperationError(error)
            }
        }
    }

    /// Reads the disclosure tones on demand and reports what could be
    /// determined. This is deliberately a manual action: the read channel is
    /// unreliable on some iOS releases (see readTonesTolerant), so it must
    /// never run automatically or gate an operation.
    func verifyToneStatus() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        AirBeepLog.shared.append("verifyToneStatus: start")

        await withBusyScreen(String(localized: "Checking the recording tone status")) { [self] in
            do {
                NetworkStatus.syncTargetHostsToAirlift()

                let backend = try accessBackend()
                let current = await readTonesTolerant(using: backend)
                let silent = try silentTones()

                let anyReadable = current.contains { $0 != nil }
                guard anyReadable else {
                    // An all-nil table is a read failure, not a state. The
                    // write may or may not have taken effect.
                    verificationMessage = String(
                        localized: "The tone status could not be checked: the read channel is unavailable on this iOS release. The last change may or may not have taken effect."
                    )
                    AirBeepLog.shared.append("verifyToneStatus: unreadable")
                    return
                }
                if Self.tones(current, equal: silent, requireAll: false) {
                    verificationMessage = String(
                        localized: "The recording tones are silenced on this device."
                    )
                    AirBeepLog.shared.append("verifyToneStatus: silenced")
                } else {
                    verificationMessage = String(
                        localized: "The original recording tones are still in place; the silence has not taken effect."
                    )
                    AirBeepLog.shared.append("verifyToneStatus: originals")
                }
            } catch {
                reportOperationError(error)
            }
        }
    }

    func restoreSystemTone() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        AirBeepLog.shared.append("restoreSystemTone: start")

        await withBusyScreen(String(localized: "Restoring original call recording tones")) { [self] in
            do {
                NetworkStatus.syncTargetHostsToAirlift()

                let backend = try accessBackend()
                let current = await readTonesTolerant(using: backend)
                let silent = try silentTones()
                let backups = try? self.readBackupsTolerant()

                guard let backups, self.isCompleteRequiredBackup(backups) else {
                    // No usable backup. If we never silenced without one, the
                    // tones were never changed and are already original.
                    guard ToneBackupStateCache.load() else {
                        self.refreshBackupState()
                        self.finishSuccess(
                            String(localized: "The original recording tones are already in place.")
                        )
                        AirBeepLog.shared.append("restoreSystemTone: no backup, already original")
                        return
                    }
                    // We silenced without a backup. Any tone that could be read
                    // and is not the bundled silence means iOS already
                    // regenerated the original disclosure audio.
                    let anyReadable = current.contains { $0 != nil }
                    if anyReadable, !Self.tones(current, equal: silent, requireAll: false) {
                        ToneBackupStateCache.save(false)
                        self.refreshBackupState()
                        self.finishSuccess(
                            String(localized: "The original recording tones were restored.")
                        )
                        AirBeepLog.shared.append("restoreSystemTone: originals already regenerated")
                        return
                    }
                    throw CallRecordingToneError.languageRestoreRequired
                }

                if Self.tones(current, equal: backups, requireAll: true) {
                    ToneBackupStateCache.save(false)
                    self.refreshBackupState()
                    self.finishSuccess(
                        String(localized: "The original recording tones are already in place.")
                    )
                    AirBeepLog.shared.append("restoreSystemTone: already original")
                    return
                }

                do {
                    AirBeepLog.shared.append("restoreSystemTone: writing original from backup")
                    try await writeTones(backups, using: backend)
                    ToneBackupStateCache.save(false)
                    self.refreshBackupState()
                    self.finishSuccess(
                        String(localized: "The original recording tones were restored.")
                    )
                    AirBeepLog.shared.append("restoreSystemTone: success")
                } catch {
                    try? await self.writeTones(current, using: backend)
                    throw error
                }
            } catch {
                reportOperationError(error)
            }
        }
    }

    private func refreshBackupState() {
        backupReady = hasCompleteRequiredBackup()
    }

    private func finishSuccess(_ message: String) {
        needsAirliftSetup = false
        lastError = nil
        successMessage = message
    }

    /// Keeps the screen awake and shows a warning banner while an operation
    /// runs, then restores normal idle behaviour.
    private func withBusyScreen(_ message: String, operation: @escaping () async -> Void) async {
        busyMessage = message
        UIApplication.shared.isIdleTimerDisabled = true
        defer {
            busyMessage = nil
            UIApplication.shared.isIdleTimerDisabled = false
        }
        await operation()
    }


    private func reportOperationError(_ error: Error) {
        // An incomplete backup is a partial success: what could be read is
        // saved. Keep backupReady as-is so the button state stays accurate.
        needsAirliftSetup = shouldOfferAirliftSetup(for: error)
        lastError = error.localizedDescription
        successMessage = nil
        AirBeepLog.shared.append("operation error: \(error.localizedDescription)")
    }

    private func accessBackend() throws -> AccessBackend {
        guard SystemCompatibility.isSupported else {
            throw CallRecordingToneError.unsupported
        }

        let pairingPath = PairingController.pairingFilePath()
        let attributes = try? FileManager.default.attributesOfItem(atPath: pairingPath)
        let size = attributes?[.size] as? Int ?? 0
        guard size > 0 else {
            throw CallRecordingToneError.pairingRequired
        }
        return .airlift(pairingPath: pairingPath)
    }

    private func shouldOfferAirliftSetup(for error: Error) -> Bool {
        guard let error = error as? CallRecordingToneError else { return false }
        switch error {
        case .pairingRequired, .airliftUnavailable, .airliftFailed:
            return true
        case .toneReadFailed:
            return true
        case .unsupported, .missingTone, .missingBackup, .invalidToneBundle,
             .verificationFailed, .languageRestoreRequired,
             .nothingToBackup, .backupIncomplete:
            return false
        }
    }

    // MARK: - Reading

    /// Reads every disclosure tone, one file at a time. The airlift read
    /// channel moves each file through AirTraffic and can fail to recover it
    /// on some iOS releases even though the write channel works, so a failed
    /// read never aborts the operation — the entry is `nil` and the caller
    /// decides how to proceed (backup fallback or language-change recovery).
    private func readTonesTolerant(using backend: AccessBackend) async -> [Data?] {
        var tones: [Data?] = []
        tones.reserveCapacity(files.count)

        for file in files {
            do {
                switch backend {
                case .airlift(let pairingPath):
                    tones.append(
                        try await AirliftToneTransport.shared.read(
                            path: file.systemPath,
                            pairingPath: pairingPath
                        )
                    )
                }
            } catch {
                if file.optional {
                    AirBeepLog.shared.append(
                        "readTones: optional tone \(file.name) unavailable (\(error.localizedDescription))"
                    )
                } else {
                    AirBeepLog.shared.append(
                        "readTones: \(file.name) could not be read (\(error.localizedDescription)); continuing"
                    )
                }
                tones.append(nil)
            }
        }

        return tones
    }

    /// Element-wise comparison of tone arrays. `nil` entries (unread tone or
    /// missing backup) count as "not equal" so the operation errs on the side
    /// of writing. With `requireAll` the comparison only matches when every
    /// entry is present and equal.
    private static func tones(_ lhs: [Data?], equal rhs: [Data?], requireAll: Bool) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for (l, r) in zip(lhs, rhs) {
            switch (l, r) {
            case (nil, _), (_, nil):
                if requireAll { return false }
            case let (l?, r?):
                guard l == r else { return false }
            }
        }
        return true
    }

    // MARK: - Silent assets & backups

    private func silentTones() throws -> [Data?] {
        try files.map { file in
            guard let url = resourceURL(for: file) else {
                throw CallRecordingToneError.invalidToneBundle
            }
            return try Data(contentsOf: url)
        }
    }

    private func resourceURL(for file: ToneFile) -> URL? {
        let bundle = Bundle.main
        return bundle.url(forResource: file.resourceName, withExtension: file.resourceExtension)
            ?? bundle.url(
                forResource: file.resourceName,
                withExtension: file.resourceExtension,
                subdirectory: "Resources"
            )
            ?? bundle.url(
                forResource: file.resourceName,
                withExtension: file.resourceExtension,
                subdirectory: "SilentTones"
            )
    }

    /// Saves a backup for every tone that was read successfully and does not
    /// already have one. Existing backups are never overwritten, and entries
    /// that are already the bundled silence are not stored as "originals".
    private func ensureBackup(_ current: [Data?]) throws {
        let silent = try silentTones()
        try FileManager.default.createDirectory(
            at: backupDirectory,
            withIntermediateDirectories: true
        )
        for (index, file) in files.enumerated() {
            guard let data = current.indices.contains(index) ? current[index] : nil else { continue }
            let url = backupURL(for: file)
            guard !FileManager.default.fileExists(atPath: url.path) else { continue }
            if let silentData = silent[index], data == silentData {
                AirBeepLog.shared.append("ensureBackup: \(file.name) is already silence, not backed up")
                continue
            }
            try data.write(to: url, options: .atomic)
            AirBeepLog.shared.append("ensureBackup: saved \(file.name)")
        }
    }

    /// Loads the backup for every tone; `nil` where no backup exists.
    private func readBackupsTolerant() throws -> [Data?] {
        try files.map { file in
            let url = backupURL(for: file)
            guard FileManager.default.fileExists(atPath: url.path) else {
                return nil
            }
            return try Data(contentsOf: url)
        }
    }

    /// A backup is usable when every required tone has a non-empty copy.
    private func isCompleteRequiredBackup(_ backups: [Data?]) -> Bool {
        guard backups.count == files.count else { return false }
        return zip(files, backups).allSatisfy { file, data in
            file.optional || (data?.isEmpty == false)
        }
    }

    private func hasCompleteRequiredBackup() -> Bool {
        guard let backups = try? readBackupsTolerant() else { return false }
        return isCompleteRequiredBackup(backups)
    }

    private func backupURL(for file: ToneFile) -> URL {
        backupDirectory.appending(path: file.backupName)
    }

    // MARK: - Writing

    /// Writes the given tones (aligned with `files`; `nil` entries are
    /// skipped) through the airlift write channel. The write channel is
    /// independent of the flaky read channel, so it stays the source of
    /// truth: its return code decides success. The read-back verification
    /// runs best-effort — it still fails the operation when a read succeeds
    /// but returns different bytes, while an unavailable read only logs.
    ///
    /// Returns `true` when every expected tone was re-read and matched. A
    /// `false` return means the re-read was unavailable, not that the write
    /// failed; the caller picks the corresponding success wording.
    @discardableResult
    private func writeTones(_ tones: [Data?], using backend: AccessBackend) async throws -> Bool {
        switch backend {
        case .airlift(let pairingPath):
            let payload = zip(files, tones).compactMap { file, data -> AirliftToneFile? in
                guard let data else { return nil }
                return AirliftToneFile(name: file.name, data: data)
            }
            guard !payload.isEmpty else { return true }
            try await AirliftToneTransport.shared.write(files: payload, pairingPath: pairingPath)
        }

        let verified = await readTonesTolerant(using: backend)
        var allVerified = true
        for (index, file) in files.enumerated() {
            guard let expected = tones.indices.contains(index) ? tones[index] : nil else { continue }
            guard verified.indices.contains(index), let actual = verified[index] else {
                AirBeepLog.shared.append(
                    "writeTones: could not re-read \(file.name) to verify; write channel reported success"
                )
                allVerified = false
                continue
            }
            guard actual == expected else {
                throw CallRecordingToneError.verificationFailed(file.name)
            }
        }
        return allVerified
    }
}
