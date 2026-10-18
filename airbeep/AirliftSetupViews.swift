import SwiftUI
import UIKit
import Network
import Combine

/// Reports whether Wi-Fi is up, which Airlift requires: LocalDevVPN does not
/// work over cellular, so the setup flow is gated on Wi-Fi.
///
/// `NWPathMonitor(requiredInterfaceType: .wifi)` is deliberately not used as
/// the decision. Once LocalDevVPN takes over the default path, that monitor
/// reports unsatisfied for the Wi-Fi interface even though en0 still carries an
/// address — which wrongly told users to connect Wi-Fi they already had. The
/// interface table is the same source the tunnel dialer uses, so Wi-Fi presence
/// is read from it instead, with the monitor only triggering re-evaluation.
@MainActor
final class AirliftWiFiMonitor: ObservableObject {
    enum Status {
        case checking
        case connected
        case disconnected
    }

    @Published private(set) var status: Status = .checking

    private let queue = DispatchQueue(label: "me.ssus.airbeep.airlift.wifi-monitor")
    private let monitor = NWPathMonitor()

    init() {
        refresh()
        // Cheap re-evaluation on generic path changes; the decision itself
        // always reads the live interface table, never the NWPath result.
        monitor.pathUpdateHandler = { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.refresh()
                }
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }

    private func refresh() {
        status = NetworkStatus.wifiActive ? .connected : .disconnected
    }
}


struct AirliftWiFiCheckingView: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text("Checking Wi-Fi…")
                .font(.headline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(24)
    }
}

struct AirliftWiFiRequiredView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            Text("Wi-Fi Required")
                .font(.largeTitle.bold())
            Text("Airlift requires an active Wi-Fi connection. LocalDevVPN does not work over cellular.")
                .foregroundStyle(.secondary)
            Text("Connect this iPhone to a Wi-Fi network to continue. AirBeep will continue automatically once Wi-Fi is available.")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(24)
    }
}

struct AirliftPairingView: View {
    let running: Bool
    let pin: String?
    let error: String?
    let onStart: () -> Void
    let onImportPairingFile: () -> Void

    /// Below iOS 26 the Settings › Developer Mode pairing UI is unavailable,
    /// so only the computer-generated pairing file path is offered.
    var onDevicePairingSupported: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            Text("Pair this iPhone")
                .font(.largeTitle.bold())
            if onDevicePairingSupported {
                Text("Start pairing, then open Settings › Privacy & Security › Developer Mode › Pair with AirBeep.")
                    .foregroundStyle(.secondary)
                if let pin {
                    Text(pin).font(.largeTitle.monospacedDigit())
                }
            } else {
                Text("This system version cannot pair directly on the iPhone. Generate a pairing file on a computer with iloader or idevice_pair, then import it here.")
                    .foregroundStyle(.secondary)
                PairingToolLinks()
            }
            if let error {
                Text(error).foregroundStyle(.red)
            }
            Spacer()
            if onDevicePairingSupported {
                Button(action: onStart) {
                    if running {
                        ProgressView("Waiting for pairing…")
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Start pairing")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(running)
            }

            // Conditional modifiers cannot use a ternary between two different
            // ButtonStyle types (Swift infers against ButtonStyle itself, which
            // has no .bordered). Apply each branch separately instead.
            if onDevicePairingSupported {
                importPairingButton
                    .buttonStyle(.bordered)
            } else {
                importPairingButton
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
    }

    private var importPairingButton: some View {
        Button(action: onImportPairingFile) {
            Label("Import pairing file", systemImage: "square.and.arrow.down")
                .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .disabled(running)
    }
}

/// Links to the two tools that can generate a pairing file on a computer.
/// Both names are proper nouns, so they are not localized.
struct PairingToolLinks: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Generate the pairing file on a computer, then import it here:")
                .font(.footnote)
                .foregroundStyle(.secondary)

            toolLink(
                name: "iloader",
                detail: String(localized: "Sideloader with pairing-file export"),
                url: "https://github.com/nab138/iloader"
            )
            toolLink(
                name: "idevice_pair",
                detail: String(localized: "Generates and saves pair records"),
                url: "https://github.com/jkcoxson/idevice_pair"
            )
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
    }

    private func toolLink(name: String, detail: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: 10) {
                Image(systemName: "desktopcomputer")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: name)
                        .font(.body.weight(.medium))
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

struct AirliftVPNView: View {
    let connectionError: String?
    let checking: Bool
    let onCheck: () -> Void
    let onPairAgain: () -> Void

    /// Live tunnel address, refreshed when the view appears so the user can see
    /// whether LocalDevVPN actually came up and on which address.
    @State private var tunnelAddress: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            Image(systemName: "network")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            Text("Connect LocalDevVPN")
                .font(.largeTitle.bold())
            Text("Open LocalDevVPN, tap Connect, then return to AirBeep.")
                .foregroundStyle(.secondary)
            Button("Open LocalDevVPN", action: openLocalDevVPN)
                .buttonStyle(.bordered)
                .controlSize(.large)
            if let connectionError {
                Text(connectionError).foregroundStyle(.red)
                Button("Pair again", action: onPairAgain)
                    .font(.footnote)
            }
            networkStatusRow
            Spacer()
            Button(action: onCheck) {
                if checking {
                    ProgressView("Checking connection…")
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Check and enter")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(checking)
        }
        .padding(24)
        .onAppear { tunnelAddress = NetworkStatus.tunnelInterfaceAddress }
    }

    /// Shows the Wi-Fi address and, when up, the VPN tunnel address. Useful when
    /// the connection fails: the tunnel address must be on the expected subnet.
    private var networkStatusRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            statusLine(
                symbol: "wifi",
                label: String(localized: "Wi-Fi"),
                value: NetworkStatus.wifiActive
                    ? (NetworkStatus.interfaces().first { $0.name == "en0" && $0.isUp }?.ipv4
                        ?? String(localized: "Connected"))
                    : String(localized: "Not connected")
            )
            statusLine(
                symbol: "network.badge.shield.half.filled",
                label: "LocalDevVPN",
                value: tunnelAddress ?? String(localized: "Not connected")
            )
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 10))
    }

    private func statusLine(symbol: String, label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .frame(width: 18)
            Text(label)
            Spacer(minLength: 8)
            Text(verbatim: value)
                .font(.footnote.monospaced())
                .multilineTextAlignment(.trailing)
        }
    }

    private func openLocalDevVPN() {
        let appURL = URL(string: "localdevvpn://")!
        let storeURL = URL(string: "https://apps.apple.com/app/id6755608044")!
        UIApplication.shared.open(appURL) { opened in
            guard !opened else { return }
            DispatchQueue.main.async {
                UIApplication.shared.open(storeURL)
            }
        }
    }
}

#Preview("Wi-Fi Required") {
    AirliftWiFiRequiredView()
}

#Preview("Pairing") {
    AirliftPairingView(running: false, pin: nil, error: nil, onStart: {}, onImportPairingFile: {})
}

#Preview("Pairing (import only)") {
    AirliftPairingView(
        running: false,
        pin: nil,
        error: nil,
        onStart: {},
        onImportPairingFile: {},
        onDevicePairingSupported: false
    )
}

#Preview("LocalDevVPN") {
    AirliftVPNView(connectionError: nil, checking: false, onCheck: {}, onPairAgain: {})
}
