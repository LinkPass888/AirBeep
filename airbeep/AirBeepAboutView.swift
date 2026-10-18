import SwiftUI

struct AirBeepAboutView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingAdvanced = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "waveform.badge.mic")
                            .font(.system(size: 42, weight: .semibold))
                            .foregroundStyle(.orange)
                            .frame(width: 78, height: 78)
                            .background(.orange.opacity(0.12), in: .circle)

                        Text("AirBeep")
                            .font(.title2.bold())
                        Text(versionText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }

                Section("Introduction") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("AirBeep backs up the call-recording disclosure tones, silences them, and restores the originals on demand. Back up before the first change so the originals are always recoverable.")
                        Text("Supported system: \(SystemCompatibility.supportedRangeDescription)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text("Later system versions cannot be supported.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Advanced") {
                    Button {
                        showingAdvanced = true
                    } label: {
                        Label("Advanced Settings", systemImage: "slider.horizontal.3")
                    }
                    Text("Set a custom device IP for the loopback connection, and inspect the live network interfaces.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Runtime Log") {
                    Label("Logs include pairing, tunnel and AirLift file operations.", systemImage: "list.bullet.rectangle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    ShareLink(item: AirBeepLog.shared.exportText()) {
                        Label("Export Log", systemImage: "square.and.arrow.up")
                    }
                    Button("Clear Log", role: .destructive) {
                        AirBeepLog.shared.clear()
                    }
                    .font(.footnote)
                }

                Section("Telegram Channel") {
                    Link(destination: URL(string: "https://t.me/linkpass666")!) {
                        Label {
                            Text("Follow Channel")
                        } icon: {
                            Image(systemName: "paperplane.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                }

            }
            .navigationTitle("About AirBeep")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingAdvanced) {
                AirBeepAdvancedSettingsView()
            }
        }
    }

    /// Marketing version plus build number, e.g. `Version 2.5.1 (9)`.
    ///
    /// Built with String(format:) rather than SwiftUI interpolation so the
    /// lookup key is the literal "%@" form present in both catalogs.
    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return String(format: String(localized: "Version %@ (%@)"), version, build)
    }
}

#Preview {
    AirBeepAboutView()
}
