import Combine
import Foundation

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
        }
    }
}

@MainActor
final class CallRecordingToneService: ObservableObject {
    enum ToneMode: Equatable {
        case checking
        case systemTone
        case silentTone
        case unavailable
    }

    static let shared = CallRecordingToneService()

    @Published private(set) var mode: ToneMode = .checking
    @Published private(set) var isBusy = false
    @Published private(set) var lastError: String?
    @Published private(set) var statusDetail: String?
    @Published private(set) var needsAirliftSetup = false

    private enum AccessBackend {
        case badQuery
        case airlift(pairingPath: String)
    }

    private struct ToneFile {
        let name: String
        let systemPath: String
        let backupName: String
        let resourceName: String
        let resourceExtension: String
    }

    private let files = [
        ToneFile(
            name: "StartDisclosureWithTone.m4a",
            systemPath: "/var/mobile/Library/CallServices/Greetings/default/StartDisclosureWithTone.m4a",
            backupName: "StartDisclosureWithTone.m4a",
            resourceName: "AirBeepStartSilence",
            resourceExtension: "m4a"
        ),
        ToneFile(
            name: "StopDisclosure.caf",
            systemPath: "/var/mobile/Library/CallServices/Greetings/default/StopDisclosure.caf",
            backupName: "StopDisclosure.caf",
            resourceName: "AirBeepStopSilence",
            resourceExtension: "caf"
        )
    ]

    private var backupDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appending(path: "AirBeepBackups", directoryHint: .isDirectory)
    }

    private init() {}

    func refresh() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            let backend = try accessBackend()
            mode = try await inspectMode(using: backend)
            statusDetail = nil
            needsAirliftSetup = false
            lastError = nil
        } catch {
            mode = .unavailable
            statusDetail = error.localizedDescription
            needsAirliftSetup = shouldOfferAirliftSetup(for: error)
            // Initial inspection must not pop an alert when setup is incomplete.
            lastError = nil
        }
    }

    func clearError() {
        lastError = nil
    }

    func applySilentTone() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            let backend = try accessBackend()
            let current = try await readTones(using: backend)
            let silent = try silentTones()
            if current == silent {
                mode = .silentTone
                statusDetail = nil
                needsAirliftSetup = false
                lastError = nil
                return
            }

            try ensureBackup(current)
            do {
                try await writeTones(silent, using: backend)
                mode = .silentTone
                statusDetail = nil
                needsAirliftSetup = false
                lastError = nil
            } catch {
                try? await writeTones(current, using: backend)
                throw error
            }
        } catch {
            reportOperationError(error)
        }
    }

    func restoreSystemTone() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            let backend = try accessBackend()
            let current = try await readTones(using: backend)
            // No backup yet means the tones have never been changed, so they are
            // already the original system tones.
            guard let backup = try? readBackups() else {
                mode = .systemTone
                statusDetail = nil
                needsAirliftSetup = false
                lastError = nil
                return
            }
            if current == backup {
                mode = .systemTone
                statusDetail = nil
                needsAirliftSetup = false
                lastError = nil
                return
            }

            do {
                try await writeTones(backup, using: backend)
                mode = .systemTone
                statusDetail = nil
                needsAirliftSetup = false
                lastError = nil
            } catch {
                try? await writeTones(current, using: backend)
                throw error
            }
        } catch {
            reportOperationError(error)
        }
    }

    private func reportOperationError(_ error: Error) {
        mode = .unavailable
        statusDetail = error.localizedDescription
        needsAirliftSetup = shouldOfferAirliftSetup(for: error)
        lastError = error.localizedDescription
    }

    private func accessBackend() throws -> AccessBackend {
        guard SystemCompatibility.isSupported else {
            throw CallRecordingToneError.unsupported
        }

        let majorVersion = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        if majorVersion >= 27 || !BadQuery.isAvailable {
            let pairingPath = PairingController.pairingFilePath()
            let attributes = try? FileManager.default.attributesOfItem(atPath: pairingPath)
            let size = attributes?[.size] as? Int ?? 0
            guard size > 0 else {
                throw CallRecordingToneError.pairingRequired
            }
            return .airlift(pairingPath: pairingPath)
        }

        return .badQuery
    }

    private func shouldOfferAirliftSetup(for error: Error) -> Bool {
        guard let error = error as? CallRecordingToneError else { return false }
        switch error {
        case .pairingRequired, .airliftUnavailable, .airliftFailed:
            return true
        case .toneReadFailed:
            return ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27
                || !BadQuery.isAvailable
        case .unsupported, .missingTone, .missingBackup, .invalidToneBundle, .verificationFailed:
            return false
        }
    }

    private func inspectMode(using backend: AccessBackend) async throws -> ToneMode {
        let current = try await readTones(using: backend)
        return current == (try silentTones()) ? .silentTone : .systemTone
    }

    private func readTones(using backend: AccessBackend) async throws -> [Data] {
        var tones: [Data] = []
        tones.reserveCapacity(files.count)

        for file in files {
            do {
                switch backend {
                case .badQuery:
                    tones.append(try BadQuery.readData(at: file.systemPath))
                case .airlift(let pairingPath):
                    tones.append(
                        try await AirliftToneTransport.shared.read(
                            path: file.systemPath,
                            pairingPath: pairingPath
                        )
                    )
                }
            } catch {
                throw mapReadError(error, file: file)
            }
        }

        return tones
    }

    private func mapReadError(_ error: Error, file: ToneFile) -> Error {
        if let error = error as? CallRecordingToneError {
            return error
        }

        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileReadNoSuchFileError {
            return CallRecordingToneError.missingTone(file.name)
        }
        return CallRecordingToneError.toneReadFailed(file.name, error.localizedDescription)
    }

    private func silentTones() throws -> [Data] {
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

    private func ensureBackup(_ current: [Data]) throws {
        if (try? readBackups()) != nil {
            return
        }
        guard current != (try silentTones()) else {
            throw CallRecordingToneError.missingBackup
        }

        try FileManager.default.createDirectory(
            at: backupDirectory,
            withIntermediateDirectories: true
        )
        for (file, data) in zip(files, current) {
            try data.write(to: backupURL(for: file), options: .atomic)
        }
    }

    private func readBackups() throws -> [Data] {
        try files.map { file in
            let url = backupURL(for: file)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw CallRecordingToneError.missingBackup
            }
            return try Data(contentsOf: url)
        }
    }

    private func backupURL(for file: ToneFile) -> URL {
        backupDirectory.appending(path: file.backupName)
    }

    private func writeTones(_ tones: [Data], using backend: AccessBackend) async throws {
        switch backend {
        case .badQuery:
            for (file, data) in zip(files, tones) {
                try BadQuery.writeData(data, to: file.systemPath)
            }
        case .airlift(let pairingPath):
            let payload = zip(files, tones).map {
                AirliftToneFile(name: $0.name, data: $1)
            }
            try await AirliftToneTransport.shared.write(files: payload, pairingPath: pairingPath)
        }

        let verified = try await readTones(using: backend)
        for (index, file) in files.enumerated() {
            guard verified.indices.contains(index), verified[index] == tones[index] else {
                throw CallRecordingToneError.verificationFailed(file.name)
            }
        }
    }
}
