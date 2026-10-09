import Foundation

/// Thread-safe runtime log collector.
///
/// The Rust/FFI layer calls the C log callback from arbitrary threads, so
/// writes are guarded by a lock and the UI drains the buffer on demand.
final class AirBeepLog {
    static let shared = AirBeepLog()

    private let lock = NSLock()
    private var lines: [String] = []
    private let capacity = 1000

    private init() {}

    /// Append a line from any thread.
    func append(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        lines.append(line)
        if lines.count > capacity {
            lines.removeFirst(lines.count - capacity)
        }
    }

    /// Return all collected lines so far and clear the buffer.
    func drain() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        let out = lines
        lines.removeAll()
        return out
    }

    /// Return all collected lines without clearing.
    func snapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return lines
    }

    /// Timestamped log text for exporting / sharing.
    func exportText() -> String {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let body = snapshot().joined(separator: "\n")
        return "AirBeep log — \(stamp)\n----------------------------\n\(body)"
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        lines.removeAll()
    }
}

/// Non-capturing C callback so it can be passed to the Airlift FFI as a
/// function pointer. Rust calls it with a NUL-terminated message string.
private let alLogBridge: @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?) -> Void = { _, msg in
    guard let msg = msg else { return }
    AirBeepLog.shared.append(String(cString: msg))
}

extension AirBeepLog {
    /// The C callback to hand to `al_exploit_read_file` / `al_exploit_write_dir`.
    /// `@convention(c)` function types are Sendable, so it can be nonisolated and
    /// passed from AirliftToneTransport's nonisolated static helpers.
    nonisolated static var ffiCallback: @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?) -> Void {
        alLogBridge
    }
}
