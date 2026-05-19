import AppKit
import SwiftUI
import Combine
import GroundLoop

@MainActor
class StatusBarController {
    private var statusItem: NSStatusItem
    private var popover: NSPopover
    private var viewModel: MenuBarViewModel
    private var cancellables = Set<AnyCancellable>()

    init(_ viewModel: MenuBarViewModel) {
        self.viewModel = viewModel
        self.popover = NSPopover()
        self.popover.contentSize = NSSize(width: 340, height: 400)
        self.popover.behavior = .transient
        self.popover.contentViewController = NSHostingController(rootView: MenuBarContentView().environmentObject(viewModel))

        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = self.statusItem.button {
            button.image = NSImage(systemSymbolName: "gauge.medium", accessibilityDescription: "LLM Usage")
            button.imagePosition = .imageLeading
            button.action = #selector(handleAction(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // Refresh menu bar label whenever usage data or refresh state changes.
        viewModel.$usageByAccountID
            .combineLatest(viewModel.$isRefreshing, viewModel.$accounts)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _, _ in
                self?.updateStatusItemLabel()
            }
            .store(in: &cancellables)

        // Also re-render when the user toggles the "show %" preference.
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusItemLabel()
            }
            .store(in: &cancellables)

        updateStatusItemLabel()
    }

    /// Show the most-constrained quota (highest used %) across all active accounts,
    /// so the menu bar functions as a glanceable "lowest remaining" indicator.
    private func updateStatusItemLabel() {
        guard let button = statusItem.button else { return }

        let activeIDs = Set(viewModel.accounts.filter { $0.isActive }.map { $0.id })
        let accountMetrics = viewModel.usageByAccountID
            .filter { activeIDs.contains($0.key) }

        guard let (accountID, mostUsedData) = accountMetrics.max(by: {
            let max1 = $0.value.metrics.map(\.usedPercent).max() ?? 0
            let max2 = $1.value.metrics.map(\.usedPercent).max() ?? 0
            return max1 < max2
        }) else {
            button.title = ""
            button.image = NSImage(
                systemSymbolName: "gauge.medium",
                accessibilityDescription: "LLM Usage"
            )
            return
        }

        guard let mostUsed = mostUsedData.metrics.max(by: { $0.usedPercent < $1.usedPercent }) else {
            button.title = ""
            button.image = NSImage(
                systemSymbolName: "gauge.medium",
                accessibilityDescription: "LLM Usage"
            )
            return
        }

        let remaining = max(0, 100 - mostUsed.usedPercent)
        let showLabel = UserDefaults.standard.object(forKey: "showRemainingPercent") as? Bool ?? true
        button.title = showLabel ? String(format: " %.0f%%", remaining) : ""

        // Use service icon instead of gauge
        if let account = viewModel.accounts.first(where: { $0.id == accountID }),
           let icon = serviceIconImage(for: account.service) {
            button.image = icon
        } else {
            button.image = NSImage(
                systemSymbolName: gaugeSymbol(forUsedPercent: mostUsed.usedPercent),
                accessibilityDescription: "LLM Usage"
            )
        }
        button.toolTip = "\(mostUsedData.account.service.displayName): \(mostUsed.label) — \(Int(remaining.rounded()))% remaining"
    }

    /// Returns the service logo as an NSImage, or nil if not available.
    private func serviceIconImage(for service: LLMService) -> NSImage? {
        guard let logoName = serviceLogoName(for: service) else { return nil }
        guard let url = Bundle.module.url(
            forResource: logoName, withExtension: "svg", subdirectory: "ServiceLogos"
        ) else { return nil }
        guard let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        return image
    }

    private func gaugeSymbol(forUsedPercent used: Double) -> String {
        if used >= 90 { return "gauge.high" }
        if used >= 60 { return "gauge.medium" }
        return "gauge.low"
    }

    @objc func handleAction(_ sender: Any?) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover(sender)
        }
    }

    func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            if let button = statusItem.button {
                // Adjust height before showing
                let height = UserDefaults.standard.double(forKey: "menuBarHeight")
                if height > 0 {
                    popover.contentSize = NSSize(width: 340, height: height)
                }
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                popover.contentViewController?.view.window?.makeKey()
            }
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()

        let prefsItem = NSMenuItem(title: "Preferences…", action: #selector(openPreferences), keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)

        let launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginItem.target = self
        launchAtLoginItem.state = viewModel.launchAtLogin ? .on : .off
        menu.addItem(launchAtLoginItem)

        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc func openPreferences() {
        NSApp.activate(ignoringOtherApps: true)
        if #available(macOS 14, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }

    @objc func toggleLaunchAtLogin() {
        viewModel.launchAtLogin.toggle()
    }
}
