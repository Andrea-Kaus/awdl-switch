import AppKit
import Network
import ServiceManagement
import SwiftUI

@MainActor
final class Controller: ObservableObject {
    @Published private(set) var mode: Mode
    @Published private(set) var triggers: [TriggerApp]
    @Published private(set) var activeTriggers: [String] = []
    @Published private(set) var usesWiFi = false
    @Published private(set) var helperStatus: SMAppService.Status = .notRegistered
    @Published private(set) var loginStatus: SMAppService.Status = .notRegistered
    @Published private(set) var appliedSuppression: Bool?
    @Published private(set) var helperError: String?
    @Published private(set) var loginError: String?

    private let usesLocalInstaller = BuildSigning.teamID == nil
    private lazy var helperRequirement = HelperService.signingRequirement(for: HelperService.name)
        ?? HelperService.bundledHelperRequirement()
    private let defaults = UserDefaults.standard
    private let daemon = SMAppService.daemon(plistName: HelperService.plistName)
    private let login = SMAppService.mainApp
    private let workspace = NSWorkspace.shared
    private let networkMonitor = NWPathMonitor()
    private var observation: NSKeyValueObservation?
    private var timer: Timer?
    private var connection: NSXPCConnection?
    private var pendingRequest: UUID?

    init() {
        mode = defaults.string(forKey: "mode").flatMap(Mode.init(rawValue:)) ?? .automatic
        triggers = defaults.data(forKey: "triggers")
            .flatMap { try? JSONDecoder().decode([TriggerApp].self, from: $0) } ?? []
    }

    func start() {
        if !defaults.bool(forKey: "configuredLoginItem") {
            defaults.set(true, forKey: "configuredLoginItem")
            if login.status == .notRegistered { setLaunchAtLogin(true) }
        }

        observation = workspace.observe(\.runningApplications, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.refresh() }
        }
        networkMonitor.pathUpdateHandler = { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        networkMonitor.start(queue: DispatchQueue(label: HelperService.appID + ".network"))
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh(force: true) }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        refresh(force: true)
    }

    func stop() {
        observation?.invalidate()
        networkMonitor.cancel()
        timer?.invalidate()
        disconnect()
    }

    func setMode(_ mode: Mode) {
        self.mode = mode
        defaults.set(mode.rawValue, forKey: "mode")
        refresh()
    }

    func addApps(relativeTo window: NSWindow) {
        let picker = NSOpenPanel()
        picker.title = "Choose Apps for Automatic Mode"
        picker.prompt = "Add"
        picker.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        picker.allowedContentTypes = [.applicationBundle]
        picker.allowsMultipleSelection = true
        picker.beginSheetModal(for: window) { [weak self, weak picker] response in
            guard response == .OK, let self, let picker else { return }
            for url in picker.urls {
                guard let id = Bundle(url: url)?.bundleIdentifier,
                      id != HelperService.appID,
                      !self.triggers.contains(where: { $0.id == id }) else { continue }
                let name = Self.displayName(at: url)
                self.triggers.append(TriggerApp(id: id, name: name))
            }
            self.saveTriggers()
        }
    }

    func removeApp(_ id: String) {
        triggers.removeAll { $0.id == id }
        saveTriggers()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        loginError = nil
        do {
            if enabled {
                try login.register()
            } else {
                try login.unregister()
            }
        } catch {
            loginError = error.localizedDescription
        }
        loginStatus = login.status
    }

    func setUpHelper() {
        guard !usesLocalInstaller else { return }
        helperError = nil
        do {
            if daemon.status == .notRegistered { try daemon.register() }
        } catch {
            if daemon.status != .requiresApproval { helperError = error.localizedDescription }
        }
        if daemon.status == .requiresApproval { openLoginItems() }
        refresh(force: true)
    }

    func openLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }

    var helperAction: String? {
        guard !usesLocalInstaller else { return nil }
        switch helperStatus {
        case .notRegistered: return "Set Up Helper…"
        case .requiresApproval: return "Approve Helper in System Settings…"
        default: return nil
        }
    }

    var statusText: String {
        switch helperStatus {
        case .notRegistered:
            return usesLocalInstaller ? "Run AWDL Switch.pkg to install the helper" : "Helper setup required"
        case .requiresApproval: return "Waiting for administrator approval"
        case .notFound: return "Bundled helper unavailable"
        default: break
        }
        if helperError != nil { return "Couldn’t change AWDL" }
        guard let appliedSuppression else { return "Checking AWDL…" }
        if mode == .automatic && !appliedSuppression {
            if triggers.isEmpty { return "AWDL is on · Add apps in Settings" }
            if !usesWiFi { return "AWDL is on · Automatic needs Wi-Fi" }
        }
        return appliedSuppression ? "AWDL is being suppressed" : "AWDL is on"
    }

    private var wantsSuppression: Bool {
        mode.suppressesAWDL(hasRunningTrigger: !activeTriggers.isEmpty, usesWiFi: usesWiFi)
    }

    private func saveTriggers() {
        triggers.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if let data = try? JSONEncoder().encode(triggers) {
            defaults.set(data, forKey: "triggers")
        }
        refresh()
    }

    private func refresh(force: Bool = false) {
        let path = networkMonitor.currentPath
        let onWiFi = path.status == .satisfied
            && path.usesInterfaceType(.wifi)
            && !path.usesInterfaceType(.wiredEthernet)
        if usesWiFi != onWiFi { usesWiFi = onWiFi }

        let selectedIDs = Set(triggers.map(\.id))
        let names = workspace.runningApplications.compactMap { app -> String? in
            guard !app.isTerminated, app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                  let id = app.bundleIdentifier, selectedIDs.contains(id) else { return nil }
            return app.localizedName ?? app.bundleURL.map(Self.displayName(at:)) ?? id
        }
        let matchingNames = Set(names).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        if activeTriggers != matchingNames { activeTriggers = matchingNames }

        let daemonStatus: SMAppService.Status = usesLocalInstaller
            ? (FileManager.default.fileExists(atPath: HelperService.installedPlist) ? .enabled : .notRegistered)
            : daemon.status
        if helperStatus != daemonStatus { helperStatus = daemonStatus }

        let currentLoginStatus = login.status
        if loginStatus != currentLoginStatus { loginStatus = currentLoginStatus }
        guard daemonStatus == .enabled else {
            disconnect()
            return
        }
        guard pendingRequest == nil, force || appliedSuppression != wantsSuppression else { return }
        applySuppression(wantsSuppression)
    }

    private static func displayName(at url: URL) -> String {
        let name = FileManager.default.displayName(atPath: url.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    private func disconnect() {
        connection?.invalidate()
        connection = nil
        pendingRequest = nil
        if appliedSuppression != nil { appliedSuppression = nil }
    }

    private func applySuppression(_ suppress: Bool) {
        guard let requirement = helperRequirement else {
            helperError = "The bundled helper’s code signature could not be read."
            return
        }
        if connection == nil {
            let connection = NSXPCConnection(machServiceName: HelperService.name, options: .privileged)
            connection.remoteObjectInterface = NSXPCInterface(with: AWDLHelperProtocol.self)
            connection.setCodeSigningRequirement(requirement)
            connection.resume()
            self.connection = connection
        }
        let token = UUID()
        pendingRequest = token
        let proxy = connection?.remoteObjectProxyWithErrorHandler { [weak self] error in
            Task { @MainActor in self?.connectionFailed(token, message: error.localizedDescription) }
        } as? AWDLHelperProtocol
        proxy?.setSuppressed(suppress) { [weak self] failure in
            Task { @MainActor in
                guard let self, self.pendingRequest == token else { return }
                self.pendingRequest = nil
                if self.helperError != failure { self.helperError = failure }
                let applied = failure == nil ? suppress : nil
                if self.appliedSuppression != applied { self.appliedSuppression = applied }
                if suppress != self.wantsSuppression { self.refresh() }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            self?.connectionFailed(token, message: "The helper didn’t respond.")
        }
    }

    private func connectionFailed(_ token: UUID, message: String) {
        guard pendingRequest == token else { return }
        if helperError != message { helperError = message }
        disconnect()
    }
}
