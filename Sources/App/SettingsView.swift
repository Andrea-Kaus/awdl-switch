import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var controller: Controller
    let addApps: () -> Void

    var body: some View {
        Form {
            Section("Automatic") {
                Text("On Wi-Fi, AWDL stays off while any selected app is running, including in the background.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    if controller.triggers.isEmpty {
                        Text("No apps selected.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(controller.triggers) { app in
                        HStack {
                            Text(app.name)
                            Spacer()
                            Button(role: .destructive) {
                                controller.removeApp(app.id)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Remove \(app.name)")
                            .help("Remove \(app.name)")
                        }
                    }
                    Button("Add Apps…", action: addApps)
                }
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: Binding(
                    get: { controller.loginStatus == .enabled || controller.loginStatus == .requiresApproval },
                    set: controller.setLaunchAtLogin
                ))
                if controller.loginStatus == .requiresApproval {
                    Button("Open Login Items…", action: controller.openLoginItems)
                }
                if let error = controller.loginError {
                    Text(error).foregroundStyle(.secondary)
                }
            }

            Section("Privileged Helper") {
                Text(controller.statusText)
                if let action = controller.helperAction {
                    Button(action, action: controller.setUpHelper)
                }
                if let error = controller.helperError {
                    Text(error).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 460, minHeight: 360)
    }
}
