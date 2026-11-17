import AppKit
import Combine
import SwiftUI

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let controller = Controller()
    private let menu = NSMenu()
    private let indicator = SuppressionIndicator()
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var changes: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: StatusIcon.itemWidth)
        item.menu = menu
        menu.delegate = self
        statusItem = item
        if let button = item.button {
            button.imagePosition = .imageOnly
            indicator.translatesAutoresizingMaskIntoConstraints = false
            indicator.isHidden = true
            indicator.setAccessibilityElement(false)
            button.addSubview(indicator)
            NSLayoutConstraint.activate([
                indicator.centerXAnchor.constraint(equalTo: button.centerXAnchor, constant: StatusIcon.indicatorOffset),
                indicator.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                indicator.widthAnchor.constraint(equalToConstant: StatusIcon.indicatorDiameter),
                indicator.heightAnchor.constraint(equalTo: indicator.widthAnchor)
            ])
        }
        changes = controller.objectWillChange.sink { [weak self] in
            Task { @MainActor in self?.updateIcon() }
        }
        controller.start()
        updateIcon()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.stop()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(NSMenuItem(title: controller.statusText, action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        for mode in Mode.allCases {
            let item = makeItem(mode.rawValue, action: #selector(changeMode(_:)))
            item.representedObject = mode.rawValue
            item.state = controller.mode == mode ? .on : .off
            menu.addItem(item)
        }
        if controller.mode == .automatic && !controller.activeTriggers.isEmpty {
            menu.addItem(.separator())
            let apps = NSMenu()
            for name in controller.activeTriggers {
                apps.addItem(NSMenuItem(title: name, action: nil, keyEquivalent: ""))
            }
            let running = NSMenuItem(title: "Running Trigger Apps", action: nil, keyEquivalent: "")
            running.submenu = apps
            menu.addItem(running)
        }
        menu.addItem(.separator())
        if let action = controller.helperAction {
            menu.addItem(makeItem(action, action: #selector(setUpHelper)))
        }
        menu.addItem(makeItem("Settings…", action: #selector(showSettings), key: ","))
        menu.addItem(makeItem("Quit AWDL Switch", action: #selector(quit), key: "q"))
    }

    private func makeItem(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func updateIcon() {
        guard let button = statusItem?.button else { return }
        switch controller.appliedSuppression {
        case true?: button.image = StatusIcon.suppressed
        case false?: button.image = StatusIcon.on
        case nil: button.image = StatusIcon.unknown
        }
        indicator.isHidden = controller.appliedSuppression != true
        button.setAccessibilityLabel("AWDL Switch · \(controller.statusText)")
        button.toolTip = "\(controller.mode.rawValue) · \(controller.statusText)"
    }

    @objc private func changeMode(_ item: NSMenuItem) {
        guard let rawValue = item.representedObject as? String, let mode = Mode(rawValue: rawValue) else { return }
        controller.setMode(mode)
    }

    @objc private func setUpHelper() {
        showSettings()
        controller.setUpHelper()
    }

    @objc private func showSettings() {
        if settingsWindow == nil {
            let content = SettingsView(controller: controller) { [weak self] in
                guard let self, let window = self.settingsWindow else { return }
                self.controller.addApps(relativeTo: window)
            }
            let window = NSWindow(contentViewController: NSHostingController(rootView: content))
            window.title = "AWDL Switch Settings"
            window.setContentSize(NSSize(width: 500, height: 410))
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

@main
struct AWDLSwitch {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
