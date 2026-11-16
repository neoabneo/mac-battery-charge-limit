import AppKit
import Combine
import BCLShared

/// The whole interface: one native menu with a 50–80% slider at the top.
@MainActor
final class LimitMenu: NSObject, NSMenuDelegate {
    let menu = NSMenu(title: "Battery Charge Limit")

    private let model: AppModel
    private let sliderRow = NSView()
    private let slider = NSSlider()
    private let limitLabel = NSTextField(labelWithString: "")
    private let stateItem = NSMenuItem()
    private let installItem = NSMenuItem()
    private var commitTask: Task<Void, Never>?
    private var cancellables: [AnyCancellable] = []

    private static let tickStepPercent = 5.0
    private static let snapRadiusPercent = 1.0

    init(model: AppModel) {
        self.model = model
        super.init()
        menu.autoenablesItems = false
        menu.delegate = self

        limitLabel.font = NSFont.systemFont(ofSize: 13)
        slider.minValue = Double(BCLSettings.limitRange.lowerBound)
        slider.maxValue = Double(BCLSettings.limitRange.upperBound)
        slider.numberOfTickMarks = Int((Double(BCLSettings.limitRange.upperBound - BCLSettings.limitRange.lowerBound) / Self.tickStepPercent)) + 1
        slider.allowsTickMarkValuesOnly = false
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(sliderChanged(_:))
        slider.translatesAutoresizingMaskIntoConstraints = false
        limitLabel.translatesAutoresizingMaskIntoConstraints = false
        sliderRow.translatesAutoresizingMaskIntoConstraints = false

        sliderRow.addSubview(limitLabel)
        sliderRow.addSubview(slider)
        NSLayoutConstraint.activate([
            sliderRow.widthAnchor.constraint(equalToConstant: 268),
            sliderRow.heightAnchor.constraint(equalToConstant: 56),
            limitLabel.leadingAnchor.constraint(equalTo: sliderRow.leadingAnchor, constant: 14),
            limitLabel.topAnchor.constraint(equalTo: sliderRow.topAnchor, constant: 8),
            limitLabel.trailingAnchor.constraint(equalTo: sliderRow.trailingAnchor, constant: -14),
            slider.leadingAnchor.constraint(equalTo: sliderRow.leadingAnchor, constant: 10),
            slider.trailingAnchor.constraint(equalTo: sliderRow.trailingAnchor, constant: -10),
            slider.topAnchor.constraint(equalTo: limitLabel.bottomAnchor, constant: 6),
        ])

        let sliderItem = NSMenuItem()
        sliderItem.view = sliderRow
        menu.addItem(sliderItem)
        menu.addItem(.separator())

        stateItem.isEnabled = false
        menu.addItem(stateItem)

        installItem.target = self
        installItem.action = #selector(installHelper(_:))
        menu.addItem(installItem)

        // No key equivalents anywhere in this app: the menu is the whole interface.
        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        quitItem.keyEquivalentModifierMask = []
        menu.addItem(quitItem)

        syncFromSettings()
        cancellables.append(model.$settings.sink { [weak self] settings in self?.syncFromSettings() })
    }

    private(set) var isOpen = false

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        model.refreshNow()
        let problem = model.helperProblem
        stateItem.isHidden = problem == nil
        stateItem.title = problem ?? ""
        installItem.isHidden = problem == nil
        installItem.title = model.helperToolInstalled ? "Reinstall helper" : "Install helper"
    }

    func menuWillOpen(_ menu: NSMenu) {
        isOpen = true
    }

    func menuDidClose(_ menu: NSMenu) {
        isOpen = false
    }

    // MARK: - Actions

    @objc private func sliderChanged(_ sender: NSSlider) {
        let raw = sender.doubleValue
        let nearestTick = (raw / Self.tickStepPercent).rounded() * Self.tickStepPercent
        // Weak magnet: within one percent of a tick the knob parks on that tick, so the four
        // percents between ticks still accept any value.
        let value = abs(nearestTick - raw) <= Self.snapRadiusPercent ? nearestTick : raw
        if value != raw { sender.doubleValue = value }
        let percent = Int(value.rounded())
        limitLabel.stringValue = "Charge limit: \(percent)%"
        model.settings.limitPercent = percent
        scheduleCommit()
    }

    @objc private func installHelper(_ sender: Any?) {
        model.installHelperTool()
    }

    /// A drag fires the action for every tick mark; coalesce it into one settings write.
    private func scheduleCommit() {
        commitTask?.cancel()
        commitTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled, let self else { return }
            self.model.commitSettings()
        }
    }

    private func syncFromSettings() {
        slider.doubleValue = Double(model.settings.limitPercent)
        limitLabel.stringValue = "Charge limit: \(model.settings.limitPercent)%"
    }
}
