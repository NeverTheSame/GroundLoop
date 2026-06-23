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

        // Check for default account first
        var targetAccountID: UUID?
        var mostUsedData: UsageData?
        var mostUsedMetric: UsageMetric?

        if let defaultID = UserDefaults.standard.string(forKey: "defaultAccountID"),
           let uuid = UUID(uuidString: defaultID),
           let defaultData = accountMetrics[uuid] {
            // Use default account
            targetAccountID = uuid
            mostUsedData = defaultData
            mostUsedMetric = defaultData.metrics.max(by: { $0.usedPercent < $1.usedPercent })
        } else if let (accountID, data) = accountMetrics.max(by: {
            let max1 = $0.value.metrics.map(\.usedPercent).max() ?? 0
            let max2 = $1.value.metrics.map(\.usedPercent).max() ?? 0
            return max1 < max2
        }) {
            // Fall back to most-constrained account
            targetAccountID = accountID
            mostUsedData = data
            mostUsedMetric = data.metrics.max(by: { $0.usedPercent < $1.usedPercent })
        }

        guard let accountID = targetAccountID,
              let data = mostUsedData,
              let mostUsed = mostUsedMetric else {
            button.title = ""
            button.contentTintColor = nil
            button.image = NSImage(systemSymbolName: "gauge.medium", accessibilityDescription: "LLM Usage")
            return
        }

        let remaining = max(0, 100 - mostUsed.usedPercent)
        let showLabel = UserDefaults.standard.object(forKey: "showRemainingPercent") as? Bool ?? true
        let account = viewModel.accounts.first(where: { $0.id == accountID })

        button.title = ""
        button.contentTintColor = nil
        button.image = makeStatusBarImage(service: account?.service, remaining: remaining, showLabel: showLabel)
        button.toolTip = "\(data.account.service.displayName): \(mostUsed.label) — \(Int(remaining.rounded()))% remaining"
    }

    /// Returns an NSColor for the menu bar indicator based on remaining quota.
    /// Green > 60%, Yellow 20–60%, Red < 20%.
    private func usageColor(remainingPercent: Double) -> NSColor {
        if remainingPercent > 60 { return .systemGreen }
        if remainingPercent > 20 { return .systemYellow }
        return .systemRed
    }

    /// Draws the service icon (tinted with the usage colour) and percentage label
    /// into a single non-template NSImage, bypassing AppKit's template recolour pass.
    private func makeStatusBarImage(
        service: LLMService?,
        remaining: Double,
        showLabel: Bool
    ) -> NSImage {
        let color = usageColor(remainingPercent: remaining)
        let labelText = showLabel ? String(format: " %.0f%%", remaining) : ""
        let font = NSFont.menuBarFont(ofSize: 0)
        let textAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]

        let iconSize: CGFloat = 16
        let textSize = labelText.isEmpty ? .zero : labelText.size(withAttributes: textAttrs)
        let totalWidth = iconSize + textSize.width
        let barHeight = NSStatusBar.system.thickness

        let image = NSImage(
            size: NSSize(width: max(totalWidth, iconSize), height: barHeight),
            flipped: false
        ) { _ in
            let iconRect = NSRect(
                x: 0,
                y: (barHeight - iconSize) / 2,
                width: iconSize,
                height: iconSize
            )

            // Load service SVG, draw it, then composite the usage colour on top.
            if let svc = service,
               let logoName = serviceLogoName(for: svc),
               let url = Bundle.module.url(
                   forResource: logoName, withExtension: "svg", subdirectory: "ServiceLogos"),
               let logo = NSImage(contentsOf: url) {
                logo.draw(in: iconRect)
                color.setFill()
                iconRect.fill(using: .sourceAtop)
            } else {
                // Fallback SF symbol
                if let fallback = NSImage(systemSymbolName: "gauge.medium", accessibilityDescription: nil) {
                    fallback.draw(in: iconRect)
                    color.setFill()
                    iconRect.fill(using: .sourceAtop)
                }
            }

            if !labelText.isEmpty {
                let textY = (barHeight - textSize.height) / 2
                labelText.draw(at: NSPoint(x: iconSize, y: textY), withAttributes: textAttrs)
            }
            return true
        }
        image.isTemplate = false
        return image
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
