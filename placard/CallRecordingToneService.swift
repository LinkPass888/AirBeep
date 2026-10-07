import Combine
import Foundation

enum CallRecordingToneError: LocalizedError {
    case unsupported
    case missingTone(String)
    case missingBackup
    case invalidToneBundle
    case verificationFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupported:
            String(localized: "This device or system version is not supported.")
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
        case modified
        case unavailable
    }

    static let shared = CallRecordingToneService()

    @Published private(set) var mode: ToneMode = .checking
    @Published private(set) var isBusy = false
    @Published private(set) var lastError: String?

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

    func refresh() {
        do {
            mode = try inspectMode()
            lastError = nil
        } catch {
            mode = .unavailable
            lastError = error.localizedDescription
        }
    }

    func clearError() {
        lastError = nil
    }

    func applySilentTone() {
        guard !isBusy else { return }
        isBusy = true
        refreshAfterOperation {
            let current = try readTones()
            let silent = try silentTones()
            if current == silent {
                mode = .silentTone
                return
            }

            try ensureBackup(current)
            do {
                try writeTones(silent)
                mode = .silentTone
            } catch {
                try? writeTones(current)
                throw error
            }
        }
    }

    func restoreSystemTone() {
        guard !isBusy else { return }
        isBusy = true
        refreshAfterOperation {
            let current = try readTones()
            let backup = try readBackups()
            if current == backup {
                mode = .systemTone
                return
            }

            do {
                try writeTones(backup)
                mode = .systemTone
            } catch {
                try? writeTones(current)
                throw error
            }
        }
    }

    private func refreshAfterOperation(_ operation: () throws -> Void) {
        defer { isBusy = false }
        do {
            try operation()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            mode = (try? inspectMode()) ?? .unavailable
        }
    }

    private func inspectMode() throws -> ToneMode {
        guard BadQuery.isAvailable else { throw CallRecordingToneError.unsupported }
        let current = try readTones()
        if current == (try silentTones()) {
            return .silentTone
        }
        if let backup = try? readBackups(), backup == current {
            return .systemTone
        }
        return .modified
    }

    private func readTones() throws -> [Data] {
        try files.map { file in
            do {
                return try BadQuery.readData(at: file.systemPath)
            } catch {
                throw CallRecordingToneError.missingTone(file.name)
            }
        }
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

    private func writeTones(_ tones: [Data]) throws {
        for (file, data) in zip(files, tones) {
            try BadQuery.writeData(data, to: file.systemPath)
            guard try BadQuery.readData(at: file.systemPath) == data else {
                throw CallRecordingToneError.verificationFailed(file.name)
            }
        }
    }
}
