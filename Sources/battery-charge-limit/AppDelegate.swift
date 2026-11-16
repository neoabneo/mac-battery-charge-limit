import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let model = AppModel()
    private lazy var limitMenu = LimitMenu(model: model)
    private var titleCancellable: AnyCancellable?
    private var placementCancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = MenuBarPlacement.apply()
        installStatusItem()

        titleCancellable = model.$menuTitle.sink { [weak self] title in self?.applyTitle(title) }
        placementCancellable = model.$telemetry.sink { [weak self] _ in self?.reassertPlacement() }

        model.start()
        // The one thing a first-time user has to do is in the menu below the slider, so the app asks
        // for it out loud rather than waiting for them to find it. Nothing is remembered, so an
        // app kept without a helper asks again on the next launch.
        if !model.helperToolInstalled { promptForInstall() }
    }

    private func promptForInstall() {
        let alert = NSAlert()
        alert.messageText = "Install the charge-control helper?"
        alert.informativeText = "Charging is controlled by the AppleSMC, which needs a small root "
            + "helper installed once with an administrator password. Until then this app only shows "
            + "the charge percentage."
        alert.addButton(withTitle: "Install helper")
        alert.addButton(withTitle: "Not now")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { model.installHelperTool() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.terminate()
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = MenuBarPlacement.autosaveName
        item.menu = limitMenu.menu
        if let button = item.button {
            button.image = nil
            button.imagePosition = .noImage
            button.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            button.title = model.menuTitle
        }
        statusItem = item
    }

    private func applyTitle(_ title: String) {
        statusItem?.button?.title = title
    }

    /// AppKit only reads the stored position when the item is created, so a rearranged menu bar is
    /// followed by rebuilding the item — which happens only after a new position value was stored.
    private func reassertPlacement() {
        guard limitMenu.isOpen == false, MenuBarPlacement.apply() else { return }
        if let existing = statusItem { NSStatusBar.system.removeStatusItem(existing) }
        installStatusItem()
    }
}
