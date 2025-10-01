# VMBar

A lightweight macOS menu bar app for managing local VMware Fusion virtual machines. VMBar lists your VMs, shows their power state at a glance, lets you perform power actions, and provides quick access to disk persistence settings; all from the menu bar.

VMBar talks to the VMware Fusion `vmrest` HTTP API for most operations and uses VMware's `vmcli` tool (with your permission) to read per-VM configuration needed to display and toggle disk modes.

## Highlights

- Menu bar UI that lists all VMs with power state icons
- Power actions: On, Off, Suspend/Resume
- Per-VM "Disks" submenu with disk mode toggles:
  - Persistent vs. Non-Persistent (independent-persistent / independent-nonpersistent)
- Uses Keychain to store `vmrest` credentials
- Uses security-scoped bookmarks to access:
  - The `vmcli` tool (or VMware Fusion.app)
  - Your "Virtual Machines" folder (to read `.vmx` config)
- Preferences window for configuring host/port and credentials

---

## Requirements

- macOS (AppKit-based; tested on recent macOS 26.0)
- Xcode (to build; Swift + Cocoa)
- VMware Fusion 13+ (or compatible version that provides `vmrest` and `vmcli`)
- `vmrest` service running and reachable (default host/port are configurable)
- Optional: local HTTP proxy at `127.0.0.1:8888` for debugging

---

## Building

1. Open the project in Xcode.
2. Build and run the "VMBar" target on macOS.

Notes:
- The app uses App Sandbox patterns via security-scoped bookmarks. You'll be prompted at first run to grant access to:
  - `vmcli` (the VMware Fusion.app bundle containing it since `vmcli` is an alias)
  - Your "Virtual Machines" folder
- The app expects a `defaultPrefs.plist` embedded in the bundle for default UserDefaults (host/port, etc.).

---

## First Run & Configuration

1. Launch the app. A menu bar icon ("MenuIcon") should appear.
2. Open Preferences... from the menu:
   - Enter your `vmrest` username and password (stored securely via Keychain).
   - Configure the host and port if needed (defaults to `127.0.0.1:8697`).
3. When you open a VM's "Disks" submenu for the first time:
   - Grant access to VMware Fusion's `vmcli` by selecting the VMware Fusion.app bundle (the app finds `Contents/Public/vmcli` or `Contents/Library/vmcli` automatically).
   - Grant access to your "Virtual Machines" folder so the app can read `.vmx` files to discover disks and their modes.
4. After granting permissions, the app will populate VMs and disks automatically.

---

## Usage

- Click the menu bar icon to open the menu.
- VM list:
  - Each VM displays a power-state icon and its display name (or ID).
- VM submenu actions:
  - Power On, Power Off, Shutdown, Suspend, Resume (Unpause).
- Disks submenu:
  - Shows discovered disks (e.g., "nvme0:0 — Virtual Disk.vmdk").
  - Toggle disk mode between:
    - Persistent ("independent-persistent")
    - Non-Persistent ("independent-nonpersistent")

The menu refreshes when opened and after actions complete. (See Roadmap)

---

## How It Works

### Networking and API

- `VMRestClient` encapsulates the VMware Fusion `vmrest` REST API.
  - Base URL defaults to `http://127.0.0.1:8697` and is configurable via UserDefaults keys:
    - `vmrestHost` (default `127.0.0.1`)
    - `vmrestPort` (default `8697`)
  - Authentication: Basic Auth using the credentials you enter in Preferences (managed by `KeychainFactory`, see below).
  - Endpoints used include:
    - GET `/api/vms` — list VMs
    - GET `/api/vms/{id}/power` — get power state
    - PUT `/api/vms/{id}/power` — perform power action (on/off/shutdown/suspend/pause/unpause)
    - GET `/api/vms/{id}/params/{name}` — get a VM parameter
    - PUT `/api/vms/{id}/params` — update a VM parameter (used for disk mode)
    - Network and shared folders endpoints are present in the client for future additions/improvments

- Debug proxy:
  - `VMRestClient` enables an HTTP proxy to `127.0.0.1:8888` (useful for tools like Proxyman/Charles).
  - To enable, set `useDebugProxy` to `true` in `VMRestClient`.

### Menu and UI

- `VMMenuController` builds the menu:
  - Fetches VMs via `VMRestClient`
  - Fetches display name and power state for each VM
  - Builds per-VM submenus for power actions and disks
  - Uses `PowerStateIconFactory` to map power states to circle icons
  - Presents Preferences and Quit items

- `AppDelegate` sets up the menu controller, registers default preferences from `defaultPrefs.plist`, and opens the Preferences window.

### Disks and vmcli

- `VMCLIHelper` runs `vmcli <vmx> ConfigParams query` and captures output.
- `VMConfigParser` parses `vmcli` output into a `[String: String]` map and extracts disk records:
  - Disk key (e.g., `nvme0:0`)
  - Backing file name (e.g., `Virtual Disk.vmdk`)
  - Disk mode (e.g., `independent-persistent`, `independent-nonpersistent`)
- `VMMenuController` then:
  - Normalizes disk mode and displays user-friendly labels
  - Calls `VMRestClient.updateVMParams` to set `<diskKey>.mode` to the desired value when toggled

### Permissions (Security-Scoped Bookmarks)

- `BookmarkManager` manages persistent, secure access to:
  - The `vmcli` binary (or VMware Fusion.app)
  - Your “Virtual Machines” folder
- The app prompts you once and then reuses saved bookmarks on subsequent launches.
- `BookmarkManager.vmcliURL(under:)` resolves the best `vmcli` path under the bookmarked root:
  - `Contents/Public/vmcli`
  - `Contents/Library/vmcli`
  - Or a directly bookmarked `vmcli`

### Credentials

- `KeychainFactory` is expected to provide:
  - `getCredentials()` returning a username/password for `vmrest`
  - A Preferences UI to set these credentials
- If credentials are missing, the menu indicates "No credentials set" and provides Preferences access.

---

## Project Structure (Key Files)

- App lifecycle
  - `AppDelegate.swift` — sets up defaults and menu controller; opens Preferences
- Menu and UI
  - `VMMenuController.swift` — builds the dynamic menu, power actions, and disks submenu
  - `PowerStateIconFactory` — maps VM power states to NSImages
  - `MenuIcon` — status bar icon asset (supply in Assets)
- Networking and models
  - `VMRestClient.swift` — typed client for `vmrest` API
  - `Models.swift` — Codable models for VMs, power, NICs, shared folders, networks, etc.
- Disk parsing and permissions
  - `VMCLIHelper.swift` — runs `vmcli` to query config params
  - `VMConfigParser` — parses `vmcli` output (provide implementation)
  - `BookmarkManager.swift` — manages security-scoped bookmarks for `vmcli` and VM folders
- Preferences and alerts
  - `PreferencesWindowController` — the Preferences UI
  - `KeychainFactory` — credentials storage/retrieval
  - `AlertPresenter` — user-facing error/info alerts)

---

## Defaults and Flags

- Default preferences loaded from `defaultPrefs.plist` at launch.
- Command-line flag:
  - `--testing` — clears persistent defaults and reloads `defaultPrefs.plist` (useful for UI testing).

---

## Troubleshooting

- "No credentials set"
  - Open Preferences and enter your `vmrest` username/password.
- "No VMs found"
  - Ensure `vmrest` is running and reachable at the configured host/port.
  - Verify your credentials are valid.
- "Failed to load disks: vmcli..."
  - Grant access to VMware Fusion.app for the `vmcli` binary when prompted.
  - Grant access to the "Virtual Machines" folder when prompted (used to read `.vmx`).
- Network calls fail or time out
  - Ensure `vmrest` is running and reachable at the configured host/port.
  - If you don't run a local proxy at `127.0.0.1:8888`, disable the debug proxy in `VMRestClient` (`useDebugProxy = false`) and rebuild.
- Menu bar icon doesn't appear
  - Ensure `MenuIcon` exists in your asset catalog.
- Resume 
  - The app uses a combination of “on” and “unpause” to resume certain states. VMWare doesn't always resume correctly (see Roadmap)

---

## Security & Privacy

- Credentials are stored in the Keychain.
- Access to `vmcli` and VM folders is explicitly granted by you and persisted via security-scoped bookmarks.
- VMBar does not transmit your data anywhere except to the configured `vmrest` endpoint.

---

## Roadmap

- Wire up start at login preference. Totally forgot to set that up. :)
- Improve resume after suspend.
- Improve menu bar auto-refresh and notifications.
- Improve unit and UI tests.
- UI for explaining need for access VMWare Fusion.app folder and the Virtual Machines folder due to App Sandbox.
- UI for Network, Shared Folders, and Host Networks (endpoints already implemented in `VMRestClient`).
- Better error surfaces, api loading, and retry mechanisms.

---

## License

The content of this project itself is licensed under the [Creative Commons Attribution 4.0 Unported license](https://creativecommons.org/licenses/by/4.0/), and the underlying source code used to format and display that content is licensed under the [MIT license](LICENSE.md).

---

## Acknowledgments

- VMware Fusion `vmrest` API and `vmcli`
- Apple AppKit and security-scoped bookmarks
