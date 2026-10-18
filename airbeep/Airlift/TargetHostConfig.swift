import Foundation

/// The device IP the Airlift tunnel dials for the loopback connection.
///
/// Priority: a user override from Advanced settings, else the build-time
/// `AirliftTargetHost` Info.plist value (from `AIRLIFT_TARGET_HOST`), else the
/// LocalDevVPN default `10.7.0.1`. The override is persisted in UserDefaults so
/// it survives relaunch and is applied before every tone operation.
enum TargetHostConfig {
    private static let key = "airliftCustomTargetHost"

    /// The build-time configured host.
    static var buildDefault: String {
        (Bundle.main.object(forInfoDictionaryKey: "AirliftTargetHost") as? String ?? "10.7.0.1")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The user's custom override, if set. Empty means "use the build default".
    static var custom: String? {
        get {
            let raw = (UserDefaults.standard.string(forKey: key) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return raw.isEmpty ? nil : raw
        }
        set {
            if let value = newValue, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                UserDefaults.standard.set(
                    value.trimmingCharacters(in: .whitespacesAndNewlines),
                    forKey: key
                )
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }

    /// The host actually dialed: custom override, else build default.
    static var effective: String {
        custom ?? buildDefault
    }

    /// True when the user has set a custom override.
    static var isCustomized: Bool {
        custom != nil
    }

    /// Validate an IPv4 dotted-quad. Returns nil when valid, otherwise a
    /// localized error message. An empty string is valid and means "reset".
    static func validate(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }

        let octets = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4 else {
            return String(localized: "Enter a valid IPv4 address, e.g. 10.7.0.1")
        }
        for octet in octets {
            guard !octet.isEmpty, octet.allSatisfy({ $0.isNumber && $0.isASCII }) else {
                return String(localized: "Enter a valid IPv4 address, e.g. 10.7.0.1")
            }
            guard let value = Int(octet), (0...255).contains(value) else {
                return String(localized: "Each part of the address must be between 0 and 255.")
            }
        }
        return nil
    }
}
