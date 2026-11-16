import AppKit
import BCLCore
import BCLShared

@MainActor
final class AppModel: ObservableObject {
    @Published var settings: BCLSettings
    @Published var telemetry: BCLTelemetry?

    /// Non-nil while the charge limit is not being enforced, which is the only time the menu shows
    /// anything besides the slider and Quit.
    @Published var helperProblem: String?
    @Published var menuTitle = "…"

    private let store = SettingsStore()
    private let client = HelperClient()
    private let localBattery = PowerSourceReader()
    private var pollingTask: Task<Void, Never>?
    private var helperStateProblem: String?
    private var actionMessage: String?
    private var appliedGeneration: Int?

    init() {
        settings = store.load()
    }

    var helperToolInstalled: Bool { client.helperToolInstalled }

    func start() {
        refreshNow()
        schedulePolling()
    }

    /// Called when the menu opens so the line under the slider reflects the current charge state.
    func refreshNow() {
        refreshMenuTitle()
        Task { [weak self] in await self?.fetchTelemetry() }
    }

    /// One UserDefaults write plus one helper call per user-visible change.
    func commitSettings() {
        settings.normalize()
        store.save(settings)
        actionMessage = nil
        Task { [weak self] in
            guard let self else { return }
            let result = await self.client.applySettings(self.settings)
            self.appliedGeneration = self.client.connectionGeneration
            if !result.ok { self.actionMessage = result.message }
            await self.fetchTelemetry()
        }
    }

    /// A helper that came back without a limit - a reboot, a KeepAlive restart, a fresh install - is
    /// reached over a connection this process has not used before, so the stored limit goes with it.
    /// This is a helper call, not a disk write.
    private func armIfNewConnection() async {
        guard client.connectionGeneration != appliedGeneration else { return }
        let result = await client.applySettings(settings)
        appliedGeneration = client.connectionGeneration
        if !result.ok { actionMessage = result.message }
    }

    /// The installer script runs as root through one administrator-password prompt.
    func installHelperTool() {
        actionMessage = nil
        helperProblem = "installing the helper…"
        let bundle = Bundle.main.bundleURL
        Task { [weak self] in
            guard let self else { return }
            let result = await Task.detached(priority: .userInitiated) {
                HelperInstaller.run(sourceBundle: bundle)
            }.value

            if !result.ok {
                self.actionMessage = result.message
            } else if bundle.path != BCLIdentity.installedAppPath {
                // The copy in /Applications is the one whose cdhash the helper now trusts, so this
                // instance hands over to it.
                NSWorkspace.shared.open(URL(fileURLWithPath: BCLIdentity.installedAppPath))
                NSApplication.shared.terminate(nil)
                return
            }
            await self.fetchTelemetry()
        }
    }

    /// Closing the connection is what makes the helper release charge control; the helper also
    /// releases it if the app disappears without this call.
    func terminate() {
        pollingTask?.cancel()
        client.closeConnection()
    }

    private func schedulePolling() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                guard !Task.isCancelled else { return }
                await self?.fetchTelemetry()
            }
        }
    }

    private func fetchTelemetry() async {
        refreshMenuTitle()
        // Without the tool on disk there is nothing to reach, and the attempt is what makes launchd
        // log a failed job lookup on every poll.
        guard client.helperToolInstalled else {
            helperStateProblem = "no helper installed · charging is controlled by macOS"
            publishStatus()
            return
        }
        await armIfNewConnection()
        guard let telemetry = await client.telemetryJSON() else {
            helperStateProblem = "the helper is installed but does not answer · reinstall it"
            publishStatus()
            return
        }
        self.telemetry = telemetry
        helperStateProblem = problem(in: telemetry)
        if telemetry.enforcementActive == true { actionMessage = nil }
        publishStatus()
    }

    /// An install or apply failure stays visible until the helper is genuinely enforcing, otherwise
    /// reopening the menu would replace it with the generic state line.
    private func publishStatus() {
        helperProblem = actionMessage ?? helperStateProblem
    }

    /// The percentage shown in the menu bar comes from the same registry entry the system battery
    /// indicator uses, so it is already correct before the helper is installed.
    private func refreshMenuTitle() {
        guard let soc = localBattery.read().socPercent ?? telemetry?.socPercent else { return }
        menuTitle = "\(soc)%"
    }

    private func problem(in telemetry: BCLTelemetry) -> String? {
        if telemetry.enforcementActive == true { return nil }
        if telemetry.chargeControlWritable == false { return "the helper cannot write the charge keys" }
        return "the helper is running but not enforcing"
    }
}
