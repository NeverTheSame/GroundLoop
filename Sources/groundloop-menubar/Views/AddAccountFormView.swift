import SwiftUI
import GroundLoop

struct AddAccountFormView: View {
    @EnvironmentObject var viewModel: MenuBarViewModel

    /// Services whose tokens GroundLoop can find on disk / in the keychain.
    /// For these we offer a "Discover" button so the user doesn't have to
    /// paste a token (and can recover accounts they accidentally deleted).
    private static let autoDiscoverable: Set<LLMService> = [
        .antigravity, .cursor, .windsurf, .claude, .copilot, .codex, .glm
    ]

    private var canAutoDiscover: Bool {
        Self.autoDiscoverable.contains(viewModel.addService)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Account").font(.headline)

            Picker("Service", selection: $viewModel.addService) {
                ForEach(LLMService.allCases.filter { service in
                    if service == .antigravity {
                        return !viewModel.accounts.contains(where: { $0.service == .antigravity })
                    }
                    return true
                }, id: \.self) { service in
                    Text(service.displayName).tag(service)
                }
            }

            if canAutoDiscover {
                Text("GroundLoop can find this token automatically — just tap Discover.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            TextField(canAutoDiscover ? "Or paste a token manually" : "Token / API Key",
                      text: $viewModel.addToken)
                .textFieldStyle(.roundedBorder)
                .disabled(viewModel.addService == .antigravity)

            TextField("Label (optional)", text: $viewModel.addLabel)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel") {
                    viewModel.showAddForm = false
                }

                if canAutoDiscover {
                    Button("Discover") {
                        Task {
                            await viewModel.discoverAndMerge(service: viewModel.addService)
                            viewModel.showAddForm = false
                        }
                    }
                    .disabled(viewModel.isDiscovering)
                }

                if viewModel.addService != .antigravity {
                    Button("Add") {
                        Task { await viewModel.addAccount() }
                    }
                    .disabled(viewModel.addToken.isEmpty)
                    .keyboardShortcut(.return)
                }
            }
        }
        .padding(16)
        .frame(width: 300)
    }
}
