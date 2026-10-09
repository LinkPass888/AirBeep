import Combine
import Network
import SwiftUI
import UniformTypeIdentifiers

/// Completes the two prerequisites used by the AirLift backend:
/// an on-device pairing record and the LocalDevVPN loopback connection.
struct AirBeepAirliftSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var pairing = PairingController.shared
    @StateObject private var wifiMonitor = AirliftWiFiMonitor()

    @State private var paired = FileManager.default.fileExists(
        atPath: PairingController.pairingFilePath()
    )
    @State private var connected = false
    @State private var checking = false
    @State private var pairingError: String?
    @State private var connectionError: String?
    @State private var isImportingPairingFile = false

    var body: some View {
        NavigationStack {
            Group {
                switch wifiMonitor.status {
                case .checking:
                    AirliftWiFiCheckingView()
                case .disconnected:
                    AirliftWiFiRequiredView()
                case .connected:
                    if connected {
                        readyView
                    } else if paired {
                        AirliftVPNView(
                            connectionError: connectionError,
                            checking: checking,
                            onCheck: checkConnection,
                            onPairAgain: {
                                paired = false
                                pairingError = nil
                                connectionError = nil
                            }
                        )
                    } else {
                        AirliftPairingView(
                            running: pairing.running,
                            pin: pairing.pairingPIN,
                            error: pairingError,
                            onStart: startPairing,
                            onImportPairingFile: {
                                isImportingPairingFile = true
                            }
                        )
                    }
                }
            }
            .navigationTitle("Airlift Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        pairing.softCancel()
                        dismiss()
                    }
                }
            }
            .fileImporter(
                isPresented: $isImportingPairingFile,
                allowedContentTypes: [.propertyList, .data, .init(filenameExtension: "plist") ?? .data],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    importPairingFile(from: url)
                }
            }
        }
    }

    private func importPairingFile(from url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        guard let data = try? Data(contentsOf: url), !data.isEmpty else {
            pairingError = "The selected file is empty or could not be read."
            return
        }
        let adopted = PairingController.syncCanonicalPairingFile(from: url.path)
        AirBeepLog.shared.append("imported pairing file: \(url.path)")
        if FileManager.default.fileExists(atPath: adopted) {
            paired = true
            pairingError = nil
        } else {
            pairingError = "The pairing file could not be adopted."
        }
    }

    private var readyView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(.green)
            Text("Airlift Ready")
                .font(.largeTitle.bold())
            Text("Pairing and LocalDevVPN are ready. Return to AirBeep to read or change the recording tones.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
        }
        .padding(24)
    }

    private func startPairing() {
        guard !pairing.running else { return }
        pairingError = nil
        Task {
            do {
                _ = try await pairing.startAndWait()
                paired = true
            } catch {
                pairingError = error.localizedDescription
            }
        }
    }

    private func checkConnection() {
        guard !checking else { return }
        checking = true
        connectionError = nil
        Task {
            defer { checking = false }
            do {
                _ = try await TendiesEngine.shared.detectPosterBoardContainer(
                    pairingPath: PairingController.pairingFilePath()
                )
                connected = true
            } catch {
                connectionError = error.localizedDescription
            }
        }
    }
}

#Preview {
    AirBeepAirliftSetupView()
}
