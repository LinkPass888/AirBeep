import Foundation

/// Supported system range follows the airlift AirTraffic sandbox escape:
/// iOS/iPadOS 18.0 through 27.2 B2. Versions outside this range are not
/// supported and the access layer reports the actual error at runtime.
enum SystemCompatibility {
    static var isSupported: Bool {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        guard version.majorVersion >= 18 else { return false }
        if version.majorVersion > 27 { return false }
        if version.majorVersion == 27 {
            if version.minorVersion > 2 { return false }
            if version.minorVersion == 2, version.patchVersion > 0 { return false }
        }
        return true
    }

    static var supportedRangeDescription: String {
        String(localized: "iOS/iPadOS 18.0–27.2 B2")
    }
}
