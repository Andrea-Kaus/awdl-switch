import Darwin
import Foundation
import OSLog
import SystemConfiguration

private final class Helper: NSObject, NSXPCListenerDelegate {
    private let queue = DispatchQueue(label: HelperService.name)
    private let logger = Logger(subsystem: HelperService.name, category: "AWDL")
    private var suppressingPeers: [UUID: uid_t] = [:]
    private var needsRestore = false
    private var lastError: String?
    private var routeCheckScheduled = false
    private var routeSource: DispatchSourceRead?
    private var timer: DispatchSourceTimer?
    private var shutdownSource: DispatchSourceSignal?

    func start() {
        timer = DispatchSource.makeTimerSource(queue: queue)
        timer?.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(100))
        timer?.setEventHandler { [weak self] in self?.maintainInterface() }
        timer?.resume()

        signal(SIGTERM, SIG_IGN)
        shutdownSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: queue)
        shutdownSource?.setEventHandler { [weak self] in
            self?.suppressingPeers.removeAll()
            self?.maintainInterface()
            exit(EXIT_SUCCESS)
        }
        shutdownSource?.resume()

        // Route events catch macOS re-enabling AWDL. The timer also covers
        // missing route events, failed changes, and console user changes.
        let descriptor = socket(PF_ROUTE, SOCK_RAW, AF_UNSPEC)
        guard descriptor >= 0 else { return }
        guard fcntl(descriptor, F_SETFL, O_NONBLOCK) == 0 else {
            close(descriptor)
            return
        }
        routeSource = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
        routeSource?.setCancelHandler { close(descriptor) }
        routeSource?.setEventHandler { [weak self] in
            var buffer = [UInt8](repeating: 0, count: 4096)
            // Bound each drain so a busy routing socket cannot starve XPC.
            for _ in 0..<16 {
                if read(descriptor, &buffer, buffer.count) <= 0 { break }
            }
            self?.scheduleRouteCheck()
        }
        routeSource?.resume()
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        let peer = Peer(helper: self, user: connection.effectiveUserIdentifier)
        connection.exportedInterface = NSXPCInterface(with: AWDLHelperProtocol.self)
        connection.exportedObject = peer
        connection.interruptionHandler = { peer.disconnect() }
        connection.invalidationHandler = { peer.disconnect() }
        connection.resume()
        return true
    }

    func update(_ peer: Peer, suppressed: Bool, reply: @escaping (String?) -> Void) {
        queue.async {
            guard !peer.disconnected else {
                reply("The helper connection closed.")
                return
            }
            guard peer.user == self.consoleUser() else {
                self.suppressingPeers.removeValue(forKey: peer.id)
                self.maintainInterface()
                reply("Only the active macOS user can change AWDL.")
                return
            }
            self.suppressingPeers[peer.id] = suppressed ? peer.user : nil
            let error = self.maintainInterface(force: true)
            if error == nil && !suppressed && self.needsRestore {
                reply("Another AWDL Switch instance is suppressing AWDL.")
            } else {
                reply(error)
            }
        }
    }

    func remove(_ peer: Peer) {
        queue.async {
            peer.disconnected = true
            self.suppressingPeers.removeValue(forKey: peer.id)
            self.maintainInterface()
        }
    }

    private func consoleUser() -> uid_t? {
        var user: uid_t = 0
        guard let name = SCDynamicStoreCopyConsoleUser(nil, &user, nil),
              name as String != "loginwindow", user != 0 else { return nil }
        return user
    }

    private func scheduleRouteCheck() {
        guard (needsRestore || !suppressingPeers.isEmpty), !routeCheckScheduled else { return }
        routeCheckScheduled = true
        queue.asyncAfter(deadline: .now() + .milliseconds(100)) {
            self.routeCheckScheduled = false
            self.maintainInterface()
        }
    }

    @discardableResult
    private func maintainInterface(force: Bool = false) -> String? {
        guard force || needsRestore || !suppressingPeers.isEmpty else { return nil }
        let user = consoleUser()
        suppressingPeers = suppressingPeers.filter { $0.value == user }
        let suppress = !suppressingPeers.isEmpty
        guard force || suppress || needsRestore else { return nil }

        if suppress { needsRestore = true }
        do {
            try AWDLInterface.setUp(!suppress)
            needsRestore = suppress
            lastError = nil
            return nil
        } catch {
            let message = error.localizedDescription
            if lastError != message {
                logger.error("\(message, privacy: .public)")
            }
            lastError = message
            return message
        }
    }
}

private final class Peer: NSObject, AWDLHelperProtocol {
    weak var helper: Helper?
    let user: uid_t
    let id = UUID()
    // Accessed only on the helper's serial queue.
    var disconnected = false

    init(helper: Helper, user: uid_t) {
        self.helper = helper
        self.user = user
    }

    func setSuppressed(_ suppressed: Bool, withReply reply: @escaping (String?) -> Void) {
        helper?.update(self, suppressed: suppressed, reply: reply)
    }

    func disconnect() {
        helper?.remove(self)
    }
}

private let clientHash = ProcessInfo.processInfo.environment[HelperService.clientHashVariable] ?? ""
guard geteuid() == 0,
      let requirement = HelperService.signingRequirement(for: HelperService.appID)
        ?? HelperService.signingRequirement(for: HelperService.appID, hash: clientHash) else {
    fputs("AWDL Switch Helper needs a system installation and a pinned client signature.\n", stderr)
    exit(EXIT_FAILURE)
}

private let helper = Helper()
helper.start()
private let listener = NSXPCListener(machServiceName: HelperService.name)
listener.setConnectionCodeSigningRequirement(requirement)
listener.delegate = helper
listener.resume()
dispatchMain()
