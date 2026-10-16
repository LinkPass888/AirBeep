import AirliftFFI
import SwiftUI

@main
struct AirBeepApp: App {
    init() {
        let host = Bundle.main.object(forInfoDictionaryKey: "AirliftTargetHost") as? String ?? "10.7.0.1"
        let result = host.withCString { al_set_target_host($0) }
        precondition(result == 0, "Could not configure the Airlift target host")
    }

    var body: some Scene {
        WindowGroup {
            AirBeepRootView()
        }
    }
}
