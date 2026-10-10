import SwiftUI

struct AirBeepAboutView: View {
    @Environment(\.dismiss) private var dismiss

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
                        Text("AirBeep silences the call-recording disclosure tone with one switch. Original tones are backed up before the first change and restored when the switch is turned off.")
                        Text("Supported system: \(SystemCompatibility.supportedRangeDescription)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
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
        }
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.2.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "4"
        return "Version \(version) (\(build))"
    }
}

#Preview {
    AirBeepAboutView()
}
