import Foundation

/// Runtime feature detection is handled by the AirLift/BadQuery access layer.
/// Do not reject a build from a static allow-list: iOS 26.0-26.6.1 and
/// 27.0-27.2 B2 are supported, and every 27.x build exposes the same operating
/// system version tuple while their build numbers differ. A false negative here
/// is worse than letting the access layer report the actual error.
enum SystemCompatibility {
    static var isSupported: Bool {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return version.majorVersion >= 26
    }

    static var supportedRangeDescription: String {
        String(localized: "iOS/iPadOS 26.0–26.6.1, or 27.0–27.2 B2")
    }
}
