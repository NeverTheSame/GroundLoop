import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject var viewModel: MenuBarViewModel

    @AppStorage("showRemainingPercent") private var showRemainingPercent = true
    @AppStorage("lowQuotaThreshold") private var lowQuotaThreshold: Double = 90
    @AppStorage("enableLowQuotaAlerts") private var enableLowQuotaAlerts = false

    @State private var showClearConfirm = false

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
            appearanceTab
                .tabItem { Label("Appearance", systemImage: "eyedropper") }
            alertsTab
                .tabItem { Label("Alerts", systemImage: "bell") }
            dataTab
                .tabItem { Label("Data", systemImage: "tray.full") }
        }
        .frame(width: 460, height: 280)
    }

    private var generalTab: some View {
        Form {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Launch at login", isOn: $viewModel.launchAtLogin)

                if let errorMessage = viewModel.launchAtLoginErrorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                Text("GroundLoop will start automatically when you log in.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Picker("Refresh every", selection: $viewModel.refreshIntervalSeconds) {
                Text("1 minute").tag(60)
                Text("5 minutes").tag(300)
                Text("15 minutes").tag(900)
                Text("30 minutes").tag(1800)
                Text("1 hour").tag(3600)
            }
            .pickerStyle(.menu)

            HStack {
                Spacer()
                Button("Refresh now") {
                    Task { await viewModel.refreshUsage() }
                }
                .disabled(viewModel.isRefreshing)
            }
        }
        .formStyle(.grouped)
    }

    private var appearanceTab: some View {
        Form {
            Toggle("Show remaining % in the menu bar", isOn: $showRemainingPercent)
            Text("When off, only the gauge icon is shown.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .formStyle(.grouped)
    }

    private var alertsTab: some View {
        Form {
            Toggle("Notify when a quota is running low", isOn: $enableLowQuotaAlerts)

            VStack(alignment: .leading) {
                HStack {
                    Text("Trigger at")
                    Slider(value: $lowQuotaThreshold, in: 50...99, step: 1)
                    Text("\(Int(lowQuotaThreshold))%")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
                Text("You'll get one notification per metric when usage crosses this threshold, and again after it resets.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .disabled(!enableLowQuotaAlerts)
        }
        .formStyle(.grouped)
    }

    private var dataTab: some View {
        Form {
            HStack {
                VStack(alignment: .leading) {
                    Text("Usage history")
                    Text("Snapshots are stored locally for up to 6 months.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Clear…", role: .destructive) {
                    showClearConfirm = true
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Delete all stored usage history?",
            isPresented: $showClearConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete History", role: .destructive) {
                viewModel.clearHistory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone. New snapshots will start recording on the next refresh.")
        }
    }
}
