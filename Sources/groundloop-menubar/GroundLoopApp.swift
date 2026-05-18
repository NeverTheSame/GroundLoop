import SwiftUI
import GroundLoop

@main
struct GroundLoopApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        Settings {
            if let viewModel = delegate.viewModel {
                PreferencesView()
                    .environmentObject(viewModel)
            } else {
                EmptyView()
            }
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var viewModel: MenuBarViewModel!
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        viewModel = MenuBarViewModel()
        statusBarController = StatusBarController(viewModel)
    }
}
