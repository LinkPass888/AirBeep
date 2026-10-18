import SwiftUI

/// Advanced settings for the loopback connection.
///
/// The main audience is users whose LocalDevVPN device IP differs from the
/// build-time default (see issues #5/#7/#8 — connection refused on
/// 172.16.0.1 / 10.7.0.1). Here they can see the live interface state and set a
/// custom device IP that is dialed before any tone operation.
struct AirBeepAdvancedSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var customHost: String = TargetHostConfig.custom ?? ""
    @State private var validationError: String?
    @State private var savedNotice: String?
    @State private var interfaces: [NetworkStatus.Interface] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Custom Device IP")
                            .font(.headline)
                        // Interpolated into String(format:) rather than Text
                        // interpolation: a SwiftUI-interpolated key would never
                        // match the "%@" catalog entry and would ship untranslated.
                        Text(String(format: String(localized: "The loopback connection dials this address. Leave it blank to use the built-in default (%@). Set it only if your LocalDevVPN uses a different device IP."), TargetHostConfig.buildDefault))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    TextField("10.7.0.1", text: $customHost)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                        .onChange(of: customHost) {
                            savedNotice = nil
                            validate()
                        }

                    if let validationError {
                        Label(validationError, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    HStack(spacing: 12) {
                        Button("Save") { save() }
                            .buttonStyle(.borderedProminent)
                            // Nothing to save while the input is empty and no
                            // override is active, or while it does not validate.
                            .disabled(validationError != nil || (customHost.isEmpty && !TargetHostConfig.isCustomized))
                        if TargetHostConfig.isCustomized {
                            Button("Reset to Default", role: .destructive) { reset() }
                                .buttonStyle(.bordered)
                        }
                    }

                    if let savedNotice {
                        Label(savedNotice, systemImage: "checkmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.green)
                    }
                }

                Section("Current Connection") {
                    LabeledContent("Target", value: TargetHostConfig.effective)
                    LabeledContent("Wi-Fi", value: NetworkStatus.wifiActive
                        ? String(localized: "Connected")
                        : String(localized: "Not connected"))
                    LabeledContent(
                        "Tunnel",
                        value: NetworkStatus.tunnelInterfaceAddress ?? String(localized: "Not connected")
                    )
                }

                Section("Network Interfaces") {
                    if interfaces.isEmpty {
                        Text("No interfaces reported.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(interfaces.enumerated()), id: \.offset) { _, iface in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: iface.name)
                                        .font(.footnote.weight(.medium))
                                    if NetworkStatus.isTunnelInterface(iface.name) {
                                        Text("Tunnel")
                                            .font(.caption2)
                                            .foregroundStyle(.orange)
                                    }
                                }
                                Spacer(minLength: 8)
                                Text(verbatim: iface.ipv4)
                                    .font(.footnote.monospaced())
                                    .foregroundStyle(iface.isUp && iface.isRunning ? .primary : .secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Advanced")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                customHost = TargetHostConfig.custom ?? ""
                interfaces = NetworkStatus.interfaces()
                validate()
            }
        }
    }

    private func validate() {
        validationError = TargetHostConfig.validate(customHost)
    }

    private func save() {
        validate()
        guard validationError == nil else { return }
        let trimmed = customHost.trimmingCharacters(in: .whitespacesAndNewlines)
        TargetHostConfig.custom = trimmed.isEmpty ? nil : trimmed
        AirBeepLog.shared.append("advanced: custom target host set to '\(TargetHostConfig.effective)'")
        // Apply immediately so the next tone operation uses it without a relaunch.
        NetworkStatus.syncTargetHostsToAirlift()
        interfaces = NetworkStatus.interfaces()
        savedNotice = String(localized: "Saved")
    }

    private func reset() {
        TargetHostConfig.custom = nil
        customHost = ""
        validationError = nil
        AirBeepLog.shared.append("advanced: custom target host cleared, using '\(TargetHostConfig.buildDefault)'")
        NetworkStatus.syncTargetHostsToAirlift()
        savedNotice = String(localized: "Reset to default")
    }
}

#Preview {
    AirBeepAdvancedSettingsView()
}
