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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                ServiceIconView(service: account.service)

                VStack(alignment: .leading, spacing: 1) {
                    Text(account.service.displayName)
                        .font(.subheadline).bold()
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
