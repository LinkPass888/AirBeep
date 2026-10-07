import Foundation

/// Runtime feature detection is handled by the AirLift/BadQuery access layer.
/// Do not reject a build from a static allow-list: iOS 27.0.1 through 27.2 beta 2
/// all expose the same operating-system version tuple, while their build numbers
/// differ. A false negative here is worse than letting the access layer report
/// the actual error.
enum SystemCompatibility {
    static var isSupported: Bool {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return version.majorVersion >= 26
    }

    static var supportedRangeDescription: String {
        String(localized: "iOS/iPadOS 26.0 or later")
    }
}
