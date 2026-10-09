import AirliftFFI
import Darwin
import Foundation

/// `RTLD_DEFAULT` is a C macro (`((void *) -2)`) that Swift cannot import from
/// the iOS SDK (`dlfcn.h` reports it as "structure not supported"). The value is
/// platform-stable and well documented, so produce the Swift equivalent on
/// demand. A plain global constant would be flagged as non-Sendable by strict
/// concurrency, so this is a small factory function instead.
private func rtlDefaultHandle() -> UnsafeMutableRawPointer? {
    UnsafeMutableRawPointer(bitPattern: -2)
}

struct AirliftToneFile: Sendable {
    let name: String
    let data: Data
}

/// Serializes the blocking AirLift calls and keeps the file-protocol details
/// out of the SwiftUI layer. The native library still does the sandbox escape;
/// this type only supplies the two disclosure files and moves the bytes across
/// the C boundary.
actor AirliftToneTransport {
    static let shared = AirliftToneTransport()

    private static let targetDirectory = "/var/mobile/Library/CallServices/Greetings/default"

    private typealias ExploitReadFileFn = @convention(c) (
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?,
        (@convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?) -> Void)?,
        UnsafeMutableRawPointer?,
        UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?,
        UnsafeMutablePointer<Int>?,
        UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
    ) -> Int32

    private typealias BytesFreeFn = @convention(c) (UnsafeMutablePointer<UInt8>?, Int) -> Void
    private typealias SetTargetFn = @convention(c) (UnsafePointer<CChar>?) -> Int32

    func read(path: String, pairingPath: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let data = try Self.readSync(path: path, pairingPath: pairingPath)
                    continuation.resume(returning: data)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func write(files: [AirliftToneFile], pairingPath: String) async throws {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try Self.writeSync(files: files, pairingPath: pairingPath)
                    continuation.resume(returning: ())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func readSync(path: String, pairingPath: String) throws -> Data {
        configureTargets()

        guard let symbol = dlsym(rtlDefaultHandle(), "al_exploit_read_file") else {
            throw CallRecordingToneError.airliftUnavailable
        }
        let readFile = unsafeBitCast(symbol, to: ExploitReadFileFn.self)

        var output: UnsafeMutablePointer<UInt8>?
        var outputLength = 0
        var outputError: UnsafeMutablePointer<CChar>?
        let result = pairingPath.withCString { pairingCString in
            path.withCString { pathCString in
                readFile(
                    pairingCString,
                    pathCString,
                    AirBeepLog.ffiCallback,
                    nil,
                    &output,
                    &outputLength,
                    &outputError
                )
            }
        }

        let message = outputError.map { String(cString: $0) }
        if let outputError {
            al_string_free(outputError)
        }

        guard result == 0 else {
            throw CallRecordingToneError.airliftFailed(message ?? "AirLift read failed (\(result)).")
        }
        guard let output else {
            throw CallRecordingToneError.airliftFailed("AirLift returned no data for \(path).")
        }
        defer { freeBytes(output, length: outputLength) }
        return Data(bytes: output, count: outputLength)
    }

    private static func writeSync(files: [AirliftToneFile], pairingPath: String) throws {
        configureTargets()

        let stagingDirectory = FileManager.default.temporaryDirectory
            .appending(path: "AirBeep-Airlift-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: stagingDirectory) }

        for file in files {
            try file.data.write(
                to: stagingDirectory.appending(path: file.name),
                options: .atomic
            )
        }

        var outputError: UnsafeMutablePointer<CChar>?
        let result = pairingPath.withCString { pairingCString in
            stagingDirectory.path.withCString { sourceCString in
                targetDirectory.withCString { targetCString in
                    al_exploit_write_dir(
                        pairingCString,
                        sourceCString,
                        targetCString,
                        AirBeepLog.ffiCallback,
                        nil,
                        &outputError
                    )
                }
            }
        }

        let message = outputError.map { String(cString: $0) }
        if let outputError {
            al_string_free(outputError)
        }

        guard result == 0 else {
            throw CallRecordingToneError.airliftFailed(message ?? "AirLift write failed (\(result)).")
        }
    }

    private static func configureTargets() {
        guard let symbol = dlsym(rtlDefaultHandle(), "al_set_target_host") else { return }
        let setTarget = unsafeBitCast(symbol, to: SetTargetFn.self)
        _ = "10.7.0.1".withCString { setTarget($0) }
    }

    private static func freeBytes(_ pointer: UnsafeMutablePointer<UInt8>, length: Int) {
        guard let symbol = dlsym(rtlDefaultHandle(), "al_bytes_free") else { return }
        let freeBytes = unsafeBitCast(symbol, to: BytesFreeFn.self)
        freeBytes(pointer, length)
    }
}
