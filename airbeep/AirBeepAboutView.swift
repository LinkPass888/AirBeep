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
                    Text("AirBeep silences the call-recording disclosure tone with one switch. The original system tones are backed up before the first change and restored when the switch is turned off. Supported system: \(SystemCompatibility.supportedRangeDescription).")
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

                Section("Author") {
                    Link(destination: URL(string: "https://t.me/LinkPass888")!) {
                        Label {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("LinkPass888")
                                Text("https://t.me/LinkPass888")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "person.crop.circle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                }

                Section("Telegram Channel") {
                    Link(destination: URL(string: "https://t.me/linkpass666")!) {
                        Label {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("LinkPass888 Channel")
                                Text("https://t.me/linkpass666")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
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
