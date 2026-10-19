import SwiftUI
import UIKit

struct AirBeepRootView: View {
    @StateObject private var service = CallRecordingToneService.shared
    @State private var showingAbout = false
    @State private var showingAirliftSetup = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    if let busyMessage = service.busyMessage {
                        busyWarning(message: busyMessage)
                    }
                    if service.needsAirliftSetup {
                        airliftSetupCard
                    }
                    toneActions
                    details
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("AirBeep")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAbout = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .accessibilityLabel("About")
                }
            }
        }
        .onAppear {
            service.refresh()
        }
        .sheet(isPresented: $showingAbout) {
            AirBeepAboutView()
        }
        .sheet(isPresented: $showingAirliftSetup, onDismiss: {
            service.refresh()
        }) {
            AirBeepAirliftSetupView()
        }
        .alert(
            "Operation Failed",
            isPresented: Binding(
                get: { service.lastError != nil },
                set: { presented in
                    if !presented {
                        service.clearError()
                    }
                }
            )
        ) {
            Button("OK") {
                service.clearError()
            }
        } message: {
            Text(service.lastError ?? "")
        }
        .alert(
            "Done",
            isPresented: Binding(
                get: { service.successMessage != nil },
                set: { presented in
                    if !presented {
                        service.clearSuccess()
                    }
                }
            )
        ) {
            Button("OK") {
                service.clearSuccess()
            }
        } message: {
            Text(service.successMessage ?? "")
        }
        .alert(
            "Tone Status",
            isPresented: Binding(
                get: { service.verificationMessage != nil },
                set: { presented in
                    if !presented {
                        service.clearVerification()
                    }
                }
            )
        ) {
            Button("OK") {
                service.clearVerification()
            }
        } message: {
            Text(service.verificationMessage ?? "")
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(.orange.gradient)
                    .frame(width: 88, height: 88)
                Image(systemName: "waveform.badge.mic")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.white)
            }

            Text("Call Recording Tone")
                .font(.title2.bold())
            Text("Back up the original disclosure tones, then silence them. Restore the originals at any time.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text(verbatim: versionLine)
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    /// System version, then app name plus version, e.g.
    /// `iOS 27.1  AirBeep v2.5.1 (9)`.
    private var versionLine: String {
        let system = ProcessInfo.processInfo.operatingSystemVersion
        let platform = UIDevice.current.userInterfaceIdiom == .pad ? "iPadOS" : "iOS"
        let systemText = "\(platform) \(system.majorVersion).\(system.minorVersion).\(system.patchVersion)"
        return "\(systemText)  AirBeep v\(appVersion)"
    }

    /// Marketing version plus build number, e.g. `2.5.1 (9)`.
    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        guard !version.isEmpty else { return build }
        guard !build.isEmpty else { return version }
        return "\(version) (\(build))"
    }

    /// Two independent actions instead of one switch: silence the tones, and
    /// either back up the originals (when no backup exists yet) or restore
    /// them. The current tone state is only shown through the manual status
    /// check — detecting it needs a device read that is unreliable on some
    /// iOS releases, so it never runs automatically.
    private var toneActions: some View {
        VStack(spacing: 14) {
            Button {
                Task { await service.applySilentTone() }
            } label: {
                Label("Silence recording tone", systemImage: "speaker.slash.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.orange)
            .disabled(service.isBusy)

            if service.backupReady {
                Button {
                    Task { await service.restoreSystemTone() }
                } label: {
                    Label("Restore original tone", systemImage: "arrow.uturn.backward.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(service.isBusy)
            } else {
                Button {
                    Task { await service.backupOriginalTones() }
                } label: {
                    Label("Back Up Original Tones", systemImage: "square.and.arrow.down.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(service.isBusy)

                Text("Original tones are backed up before the first change.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { await service.verifyToneStatus() }
            } label: {
                Label("Check tone status", systemImage: "checkmark.seal")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(service.isBusy)

            if service.isBusy {
                ProgressView()
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
    }

    private func busyWarning(message: String) -> some View {
        Label {
            Text(message)
                .font(.headline)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.red.opacity(0.12), in: .rect(cornerRadius: 16))
    }

    private var airliftSetupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Airlift Setup Required", systemImage: "link.badge.plus")
                .font(.headline)

            Text("Pair this iPhone and connect LocalDevVPN to allow AirBeep to access the recording tone files.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                showingAirliftSetup = true
            } label: {
                Label("Open Airlift Setup", systemImage: "gearshape")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Start and stop sounds are replaced with equal-length silence.", systemImage: "waveform.slash")
            Label("Changing the system language will force the original tones back.", systemImage: "globe")
            Label(
                "The periodic tone during a long recording lives on the read-only system volume and cannot be replaced.",
                systemImage: "bell.slash"
            )
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    AirBeepRootView()
}
