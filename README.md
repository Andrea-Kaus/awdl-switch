# AWDL Switch

AWDL Switch is a native Swift menu bar app for macOS 13 or later. It controls Apple Wireless Direct Link, which AirDrop and some Continuity features use.

| Mode | Behavior |
| --- | --- |
| AWDL On | Brings AWDL up. |
| AWDL Off | Keeps AWDL down until you switch modes or quit AWDL Switch. |
| Automatic | Keeps AWDL down on Wi-Fi while an app selected in Settings is running. Background and minimized apps count. AWDL comes back up when the last selected app quits or the active connection leaves Wi-Fi. |

Automatic is the default mode and starts with an empty app list. In **Settings → Automatic**, choose **Add Apps…** to include Steam, GeForce NOW, or any other Mac app. Your mode and app list are saved, and launch at login is enabled by default on first launch.

The menu-bar switch is closed when AWDL is on. It opens and shows a green dot when the helper confirms AWDL is suppressed.

## Build and install

For use on your own Mac, run `./build.sh` with the macOS Swift toolchain selected. Quit any running copy of AWDL Switch, then open `.build/AWDL Switch.pkg` and approve the installation in macOS Installer. The package installs the app in Applications and registers its bundled helper. Open the installed app from Applications. During normal use, changing modes and starting at login use the installed helper without additional administrator prompts.

To check the installation, choose **AWDL Off** in the menu and run `/sbin/ifconfig awdl0`. The flags should omit `UP`. Choose **AWDL On** and run the command again to check that `UP` returns.

### Build with an Apple signing identity

If you have an Apple Development or Developer ID Application identity in your keychain, you can build an app that registers its helper directly:

```sh
AWDL_SIGNING_IDENTITY="Apple Development: Your Name (CERTIFICATE_ID)" \
AWDL_TEAM_ID="YOURTEAMID" \
./build.sh
```

Use the associated 10-character Team ID. Run `security find-identity -v -p codesigning` to list signing identities. The build targets your Mac’s architecture and writes `.build/AWDL Switch.app`.

1. Move the signed app to Applications and open it.
2. Open the circuit-switch icon in the menu bar and choose **Set Up Helper…**.
3. In the Login Items section of System Settings, approve AWDL Switch’s background helper with an administrator account. The approval persists for subsequent launches.

On approval, the menu shows whether AWDL is on or suppressed. If the helper can’t change AWDL, its error appears in Settings. **Launch at login** can be changed there independently.

## How it works

The app tracks running application bundles through `NSWorkspace`. The bundled daemon accepts requests from the verified app in the active macOS session. The local installer pins the exact app build in the system launch configuration, and the app pins the helper that shipped with it. Install an updated local build through its package so both pins are updated together. The Apple-signed build instead registers with `SMAppService` and verifies the signing team and identifier on each side.

The helper’s sole operation is setting the state of `awdl0`. It watches routing events and reasserts suppression if macOS brings the interface up. Quitting AWDL Switch or losing the app’s XPC connection releases its suppression request and allows the helper to restore AWDL.

Inspired by [AWDLControl](https://github.com/james-howard/AWDLControl).
