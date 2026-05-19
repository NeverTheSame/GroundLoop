import SwiftUI
import GroundLoop

struct AccountRowView: View {
    @EnvironmentObject var viewModel: MenuBarViewModel
    @Environment(\.openURL) var openURL
    let account: LLMAccount

    private var usageData: UsageData? { viewModel.usageByAccountID[account.id] }
    private var errorState: AccountErrorState? { viewModel.errorByAccountID[account.id] }

    @State private var isEditingLabel = false
    @State private var tempLabel = ""
    @ObservedObject private var hiddenStore = HiddenMetricsStore.shared
    @AppStorage("defaultAccountID") private var defaultAccountIDString: String?

    private var defaultAccountID: UUID? {
        guard let string = defaultAccountIDString else { return nil }
        return UUID(uuidString: string)
    }

    private var isDefault: Bool { defaultAccountID == account.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                ZStack(alignment: .topLeading) {
                    ServiceIconView(service: account.service)

                    if isDefault {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundColor(.yellow)
                            .offset(x: 12, y: -4)
                    }
                }

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(account.service.displayName)
                            .font(.subheadline).bold()
                        if isDefault {
                            Text("Default")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    Text(account.label)
                        .font(.caption).foregroundColor(.secondary)
                }

                Spacer()

                if let plan = usageData?.plan?.name {
                    Text(plan)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary)
                        .cornerRadius(4)
                }

                if let settingURL = usageData?.settingURL {
                    Button {
                        openURL(settingURL)
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Open settings")
                }

                Button {
                    viewModel.historyAccount = account
                } label: {
                    Image(systemName: "chart.xyaxis.line")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Show 6-month history")

                Button {
                    defaultAccountIDString = isDefault ? nil : account.id.uuidString
                } label: {
                    Image(systemName: isDefault ? "star.fill" : "star")
                        .foregroundColor(isDefault ? .yellow : .secondary)
                }
                .buttonStyle(.plain)
                .help(isDefault ? "Remove as default" : "Make default for menubar")

                Button {
                    hiddenStore.hideAccount(account.id)
                } label: {
                    Image(systemName: "eye.slash")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Hide this account")

                Button {
                    Task { await viewModel.deleteAccount(account) }
                } label: {
                    Image(systemName: "minus.circle")
                        .foregroundColor(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("Remove account")
            }

            if let errorState {
                Text(errorState.message)
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(2)
                if errorState.canLaunchAntigravity {
                    Button("Launch Antigravity") {
                        viewModel.launchAntigravity()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            } else if let data = usageData {
                if data.metrics.isEmpty {
                    Text("No usage data")
                        .font(.caption).foregroundColor(.secondary)
                } else {
                    let visible = data.metrics.filter {
                        !hiddenStore.isHidden(accountID: account.id, metricLabel: $0.label)
                    }
                    ForEach(Array(visible.enumerated()), id: \.offset) { _, metric in
                        MetricRowView(metric: metric, onHide: {
                            hiddenStore.hide(accountID: account.id, metricLabel: metric.label)
                        })
                    }
                    let hiddenCount = hiddenStore.hiddenCount(accountID: account.id)
                    if hiddenCount > 0 {
                        Button {
                            hiddenStore.unhideAll(accountID: account.id)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "eye")
                                Text("\(hiddenCount) hidden — show")
                            }
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Show hidden metrics for this account")
                    }
                }
            } else {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Loading...").font(.caption).foregroundColor(.secondary)
                }
            }
        }
        .padding(10)
        .background(.background.opacity(0.5))
        .cornerRadius(8)
        .contextMenu {
            Button("Edit Label") {
                tempLabel = account.label
                isEditingLabel = true
            }
            
            Button("Remove Account", role: .destructive) {
                Task { await viewModel.deleteAccount(account) }
            }
        }
        .alert("Edit Label", isPresented: $isEditingLabel) {
            TextField("Label", text: $tempLabel)
            Button("Cancel", role: .cancel) { }
            Button("Save") {
                Task { await viewModel.updateAccountLabel(account, newLabel: tempLabel) }
            }
        } message: {
            Text("Enter a new label for this account.")
        }
    }
}
