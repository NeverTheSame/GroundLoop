import SwiftUI

struct FooterView: View {
    @EnvironmentObject var viewModel: MenuBarViewModel

    var body: some View {
        HStack {
            if viewModel.isRefreshing || viewModel.isDiscovering {
                ProgressView().controlSize(.small)
                Text(viewModel.isDiscovering ? "Discovering..." : "Refreshing...")
                    .font(.caption2).foregroundColor(.secondary)
            } else if let date = viewModel.lastRefreshed {
                Text("Updated \(date, style: .relative) ago")
                    .font(.caption2).foregroundColor(.secondary)
            }

            Spacer()

            Button {
                openPreferences()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .help("Preferences")

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .font(.caption)
        }
        .padding(12)
    }

    private func openPreferences() {
        NSApp.activate(ignoringOtherApps: true)
        if #available(macOS 14, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
}
