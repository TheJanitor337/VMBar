import Cocoa

/// Describes a virtual machine hard disk as parsed from a VM configuration.
///
/// This model is used for building the "Disks" submenu and mapping
/// between the VM's disk key, its backing file name, and its persistence mode.
struct VMHardDisk {
    /// Backing mode of a virtual disk.
    enum Mode: String {
        /// Writes are committed to disk and persist across power cycles.
        case persistent
        /// Writes are discarded on power off; the base disk remains unchanged.
        case nonPersistent
        /// Fallback when the mode cannot be determined.
        case unknown
    }
    
    /// The configuration key for the disk (e.g. "nvme0:0").
    let key: String        // e.g. "nvme0:0"
    /// The file name of the backing disk (e.g. "Virtual Disk.vmdk").
    let fileName: String   // e.g. "Virtual Disk.vmdk"
    /// The parsed persistence mode for the disk.
    let mode: Mode
}

/// Controls the app's NSStatusItem and builds a dynamic menu that reflects
/// the current state of available VMs and their disks.
///
/// Responsibilities:
/// - Creates and manages the status bar item and its menu.
/// - Fetches VM list, display names, and power states via `VMRestClient`.
/// - Builds per-VM submenus with power actions and a "Disks" submenu.
/// - Reads VM configuration via `vmcli` (through `VMCLIHelper`) to list disks.
/// - Uses `BookmarkManager` to request and use security-scoped bookmarks for
///   the `vmcli` tool and individual VM folders.
/// - Provides actions to toggle disk persistence via the REST API.
///
/// Threading:
/// - Network and parsing callbacks may occur off the main thread.
/// - All NSMenu mutations are dispatched to the main queue.
/// - Uses a DispatchGroup to aggregate per-VM asynchronous calls before
///   finalizing the menu.
///
/// User-facing errors:
/// - When credentials are missing or operations fail, appropriate menu items
///   or alerts are presented.
final class VMMenuController: NSObject, NSMenuDelegate {
    /// The status bar item shown in the system status bar.
    private let statusItem: NSStatusItem
    /// Callback invoked when the user selects Preferences from the menu.
    private let openPreferences: () -> Void
    
    /// Creates a menu controller and status item.
    /// - Parameter openPreferences: A closure invoked to present the app's preferences window.
    init(openPreferences: @escaping () -> Void) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.openPreferences = openPreferences
        super.init()
    }
    
    /// Initializes the status item's appearance and builds the initial menu.
    ///
    /// Call this once during app startup after creating the controller.
    func start() {
        if let button = statusItem.button {
            button.image = NSImage(named: NSImage.Name("MenuIcon"))
        }
        rebuildMenu()
    }
    
    // MARK: - Menu lifecycle
    
    /// Creates a new base NSMenu and assigns this object as its delegate.
    /// - Returns: A new, empty menu ready to be populated.
    private func makeBaseMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        return menu
    }
    
    /// Rebuilds the entire status item menu.
    ///
    /// This method:
    /// - Resolves credentials via `KeychainFactory`.
    /// - Fetches the list of VMs via `VMRestClient`.
    /// - For each VM, fetches displayName and power state (in parallel).
    /// - Sorts VMs by display name and populates the menu.
    /// - Appends static items (Preferences, Quit).
    ///
    /// All UI updates are performed on the main thread.
    func rebuildMenu() {
        let menu = makeBaseMenu()
        
        guard let credentials = KeychainFactory.shared.getCredentials() else {
            menu.addItem(withTitle: "No credentials set", action: nil, keyEquivalent: "")
            buildStaticMenuItems(into: menu)
            statusItem.menu = menu
            return
        }
        
        let client = VMRestClient(username: credentials.username, password: credentials.password)
        
        client.fetchVMs { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let vms):
                DispatchQueue.main.async {
                    if vms.isEmpty {
                        menu.addItem(withTitle: "No VMs found", action: nil, keyEquivalent: "")
                        self.buildStaticMenuItems(into: menu)
                        self.statusItem.menu = menu
                        return
                    }
                }
                
                let group = DispatchGroup()
                var vmItems: [NSMenuItem] = []
                
                for vm in vms {
                    group.enter()
                    
                    // Fetch displayName first; fallback to model's displayName or id.
                    client.fetchVMParam(vmId: vm.id, paramName: "displayName") { displayResult in
                        let displayName: String
                        switch displayResult {
                        case .success(let param): displayName = param.value
                        case .failure: displayName = vm.displayName ?? vm.id
                        }
                        
                        // Then fetch power state and build the per-VM menu item.
                        client.getPowerState(vmId: vm.id) { powerResult in
                            defer { group.leave() }
                            
                            switch powerResult {
                            case .success(let powerState):
                                let vmItem = self.buildVMMenuItem(vm: vm, displayName: displayName, powerState: powerState, client: client)
                                vmItems.append(vmItem)
                            case .failure(let error):
                                print("Failed to fetch power state for \(vm.id): \(error)")
                                let vmItem = self.buildVMMenuItem(vm: vm, displayName: displayName, powerState: VMPowerState(powerState: "unknown"), client: client)
                                vmItems.append(vmItem)
                            }
                        }
                    }
                }
                
                group.notify(queue: .main) {
                    let sorted = vmItems.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
                    for item in sorted { menu.addItem(item) }
                    self.buildStaticMenuItems(into: menu)
                    self.statusItem.menu = menu
                }
                
            case .failure(let error):
                DispatchQueue.main.async {
                    print("Failed to fetch VMs: \(error)")
                    menu.addItem(withTitle: "No VMs found", action: nil, keyEquivalent: "")
                    self.buildStaticMenuItems(into: menu)
                    self.statusItem.menu = menu
                }
            }
        }
    }
    
    /// NSMenuDelegate callback used to refresh dynamic content each time the menu opens.
    /// - Parameter menu: The menu that is about to open.
    func menuWillOpen(_ menu: NSMenu) {
        // Refresh dynamic info when the menu opens
        rebuildMenu()
    }
    
    // MARK: - VM Menu Building
    
    /// Builds a top-level menu item for a VM, including power actions and a "Disks" submenu.
    ///
    /// - Parameters:
    ///   - vm: The VM model used to identify and act upon the VM.
    ///   - displayName: The human-readable name to show for the VM.
    ///   - powerState: The current power state which determines enabled actions and icon.
    ///   - client: A REST client to perform actions (not retained).
    /// - Returns: A configured NSMenuItem with a populated submenu.
    private func buildVMMenuItem(vm: VMModel, displayName: String, powerState: VMPowerState, client: VMRestClient) -> NSMenuItem {
        let title = displayName
        let stateImage = PowerStateIconFactory.image(for: powerState.powerState)
        
        let vmItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        vmItem.image = stateImage
        
        let vmSubMenu = NSMenu()
        
        // Power On
        let powerOnItem = NSMenuItem(title: "Power On", action: #selector(self.powerOnVM(_:)), keyEquivalent: "")
        powerOnItem.representedObject = vm
        let isPowerOnEnabled = powerState.isPoweredOn == false && !(powerState.isPaused || powerState.isSuspended)
        if isPowerOnEnabled {
            powerOnItem.isEnabled = true
            powerOnItem.target = self
        }
        vmSubMenu.addItem(powerOnItem)
        
        // Power Off
        let powerOffItem = NSMenuItem(title: "Power Off", action: #selector(self.powerOffVM(_:)), keyEquivalent: "")
        powerOffItem.representedObject = vm
        // Note: This is enabled when VM is on and not both paused and suspended at the same time.
        let isPowerOffEnabled = powerState.isPoweredOn && (!powerState.isPaused || !powerState.isSuspended)
        if isPowerOffEnabled {
            powerOffItem.isEnabled = true
            powerOffItem.target = self
        }
        vmSubMenu.addItem(powerOffItem)
        
        // Suspend / Resume
        if powerState.isPoweredOn {
            let suspendItem = NSMenuItem(title: "Suspend", action: #selector(self.suspendVM(_:)), keyEquivalent: "")
            suspendItem.representedObject = vm
            suspendItem.isEnabled = true
            suspendItem.target = self
            vmSubMenu.addItem(suspendItem)
        } else if powerState.isSuspended || powerState.isPaused {
            let suspendItem = NSMenuItem(title: "Resume", action: #selector(self.unpauseVM(_:)), keyEquivalent: "")
            suspendItem.representedObject = vm
            let isSuspendEnabled = true
            if isSuspendEnabled {
                suspendItem.isEnabled = true
                suspendItem.target = self
            }
            vmSubMenu.addItem(suspendItem)
        }
        
        // Disks submenu (populated asynchronously via vmcli)
        let disksItem = NSMenuItem(title: "Disks", action: nil, keyEquivalent: "")
        let disksMenu = NSMenu()
        disksItem.submenu = disksMenu
        
        // Placeholder while loading
        let loadingItem = NSMenuItem(title: "Loading…", action: nil, keyEquivalent: "")
        loadingItem.isEnabled = false
        disksMenu.addItem(loadingItem)
        
        vmSubMenu.addItem(NSMenuItem.separator())
        vmSubMenu.addItem(disksItem)
        
        // Populate disks using vmcli + VMConfigParser
        populateDisksSubmenu(disksMenu, for: vm)
        
        vmItem.submenu = vmSubMenu
        return vmItem
    }
    
    /// Populates the provided submenu with disk items for the given VM.
    ///
    /// This method:
    /// - Ensures access to the `vmcli` binary via `BookmarkManager`.
    /// - Ensures access to the VM's folder (to read its config) via `BookmarkManager`.
    /// - Executes `VMCLIHelper` to fetch the VM's config parameters.
    /// - Uses `VMConfigParser` to derive disk records.
    /// - Adds per-disk submenus with toggles for Persistent / Non-Persistent.
    ///
    /// All UI updates occur on the main thread. Any missing permissions will
    /// present menu items to prompt the user to grant access.
    ///
    /// - Parameters:
    ///   - submenu: The "Disks" submenu to populate.
    ///   - vm: The VM whose disks should be listed.
    private func populateDisksSubmenu(_ submenu: NSMenu, for vm: VMModel) {
        // Ensure access to vmcli
        BookmarkManager.shared.beginAccessVMCLI { [weak self] bookmarkedRoot, vmcliToken in
            guard let self = self else { return }
            
            guard let rootURL = bookmarkedRoot, let vmcliToken = vmcliToken else {
                DispatchQueue.main.async {
                    submenu.removeAllItems()
                    let grant = NSMenuItem(title: "Grant access to vmcli…", action: #selector(self.promptForVMCLIFolder), keyEquivalent: "")
                    grant.target = self
                    submenu.addItem(grant)
                }
                return
            }
            
            // Resolve the actual vmcli URL under the bookmarked root
            let vmcliURL = BookmarkManager.shared.vmcliURL(under: rootURL)
            
            // Ensure access to VM folder (reading config)
            BookmarkManager.shared.beginAccessVMFolder(for: vm.path) { [weak self] vmFolderURL, vmFolderToken in
                guard let self = self else { return }
                
                DispatchQueue.main.async {
                    submenu.removeAllItems()
                    
                    guard vmFolderURL != nil, let vmFolderToken = vmFolderToken else {
                        let grantFolder = NSMenuItem(title: "Grant access to VM folder…", action: #selector(self.promptForVMFolderFromMenu(_:)), keyEquivalent: "")
                        grantFolder.representedObject = vm.path
                        grantFolder.target = self
                        submenu.addItem(grantFolder)
                        _ = vmcliToken
                        return
                    }
                    
                    VMCLIHelper.runVMCLIConfigParamsQueryParsed(withVMXPath: vm.path, vmcliURL: vmcliURL) { result in
                        DispatchQueue.main.async {
                            submenu.removeAllItems()
                            switch result {
                            case .success(let config):
                                let diskRecords = VMConfigParser.disks(from: config)
                                if diskRecords.isEmpty {
                                    submenu.addItem(withTitle: "No disks found", action: nil, keyEquivalent: "")
                                } else {
                                    for record in diskRecords {
                                        let modeString = VMConfigParser.normalizedMode(from: record.rawMode)
                                        let mode: VMHardDisk.Mode
                                        switch modeString {
                                        case "persistent": mode = .persistent
                                        case "nonpersistent": mode = .nonPersistent
                                        default: mode = .persistent
                                        }
                                        
                                        let disk = VMHardDisk(key: record.key, fileName: record.fileName, mode: mode)
                                        let diskItem = NSMenuItem(title: self.displayName(for: disk), action: nil, keyEquivalent: "")
                                        let diskMenu = NSMenu()
                                        
                                        let ctx = DiskActionContext(vmId: vm.id, diskKey: disk.key)
                                        
                                        let persistent = NSMenuItem(title: "Persistent", action: #selector(self.setDiskPersistent(_:)), keyEquivalent: "")
                                        persistent.representedObject = ctx
                                        persistent.state = (disk.mode == .persistent) ? .on : .off
                                        persistent.target = self
                                        diskMenu.addItem(persistent)
                                        
                                        let nonPersistent = NSMenuItem(title: "Non-Persistent", action: #selector(self.setDiskNonPersistent(_:)), keyEquivalent: "")
                                        nonPersistent.representedObject = ctx
                                        nonPersistent.state = (disk.mode == .nonPersistent) ? .on : .off
                                        nonPersistent.target = self
                                        diskMenu.addItem(nonPersistent)
                                        
                                        diskItem.submenu = diskMenu
                                        submenu.addItem(diskItem)
                                    }
                                }
                            case .failure(let error):
                                submenu.addItem(withTitle: "Failed to load disks: \(error.localizedDescription)", action: nil, keyEquivalent: "")
                            }
                            // Explicitly keep tokens alive until after UI update.
                            _ = vmcliToken
                            _ = vmFolderToken
                        }
                    }
                }
            }
        }
    }
    
    /// Builds a user-facing display name for a disk using its key and file name.
    /// - Parameter disk: The disk to display.
    /// - Returns: A string like "nvme0:0 — Virtual Disk.vmdk" or the key if the name is empty.
    private func displayName(for disk: VMHardDisk) -> String {
        let name = (disk.fileName as NSString).lastPathComponent
        return name.isEmpty ? disk.key : "\(disk.key) — \(name)"
    }
    
    /// Context object carried in NSMenuItem.representedObject for disk actions.
    private struct DiskActionContext {
        let vmId: String
        let diskKey: String
    }
    
    // MARK: - Disk actions (via VMRestClient.updateVMParams)
    
    /// Sets the selected disk to persistent mode using the REST API.
    /// - Parameter sender: The menu item whose representedObject contains `DiskActionContext`.
    @objc private func setDiskPersistent(_ sender: NSMenuItem) {
        guard let ctx = sender.representedObject as? DiskActionContext else { return }
        setDiskMode(vmId: ctx.vmId, diskKey: ctx.diskKey, to: "independent-persistent")
    }
    
    /// Sets the selected disk to non-persistent mode using the REST API.
    /// - Parameter sender: The menu item whose representedObject contains `DiskActionContext`.
    @objc private func setDiskNonPersistent(_ sender: NSMenuItem) {
        guard let ctx = sender.representedObject as? DiskActionContext else { return }
        setDiskMode(vmId: ctx.vmId, diskKey: ctx.diskKey, to: "independent-nonpersistent")
    }
    
    /// Updates a disk's persistence mode on the server and rebuilds the menu on success.
    ///
    /// - Parameters:
    ///   - vmId: The identifier of the VM.
    ///   - diskKey: The disk key (e.g. "nvme0:0").
    ///   - to: The raw parameter value to set (e.g. "independent-persistent").
    private func setDiskMode(vmId: String, diskKey: String, to newValue: String) {
        guard let credentials = KeychainFactory.shared.getCredentials() else {
            AlertPresenter.show(messageText: "Missing Credentials",
                                informativeText: "Please set credentials in Preferences.")
            return
        }
        let client = VMRestClient(username: credentials.username, password: credentials.password)
        let paramName = "\(diskKey).mode"
        let param = VMParameter(name: paramName, value: newValue)
        
        client.updateVMParams(vmId: vmId, parameters: param) { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self.rebuildMenu()
                case .failure(let error):
                    AlertPresenter.show(messageText: "Failed to Update Disk Mode",
                                        informativeText: error.localizedDescription)
                }
            }
        }
    }
    
    // MARK: - Static items
    
    /// Appends static menu items (separator, Preferences, Quit) to the provided menu.
    /// - Parameter menu: The menu to modify.
    private func buildStaticMenuItems(into menu: NSMenu) {
        menu.addItem(NSMenuItem.separator())
        
        let prefs = NSMenuItem(title: "Preferences…", action: #selector(openPreferencesAction), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)
        
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }
    
    /// Invokes the provided `openPreferences` closure.
    @objc private func openPreferencesAction() {
        openPreferences()
    }
    
    // MARK: - VM Actions
    
    /// Powers on the VM associated with the sender menu item.
    /// - Parameter sender: Menu item with `VMModel` in its representedObject.
    @objc private func powerOnVM(_ sender: NSMenuItem) {
        guard let vm = sender.representedObject as? VMModel else { return }
        performVMAction(vm, action: "on")
    }

    /// Powers off the VM associated with the sender menu item.
    /// - Parameter sender: Menu item with `VMModel` in its representedObject.
    @objc private func powerOffVM(_ sender: NSMenuItem) {
        guard let vm = sender.representedObject as? VMModel else { return }
        performVMAction(vm, action: "off")
    }
    
    /// Requests a guest OS shutdown for the VM associated with the sender menu item.
    /// - Parameter sender: Menu item with `VMModel` in its representedObject.
    @objc private func shutdownVM(_ sender: NSMenuItem) {
        guard let vm = sender.representedObject as? VMModel else { return }
        performVMAction(vm, action: "shutdown")
    }

    /// Suspends the VM associated with the sender menu item.
    /// - Parameter sender: Menu item with `VMModel` in its representedObject.
    @objc private func suspendVM(_ sender: NSMenuItem) {
        guard let vm = sender.representedObject as? VMModel else { return }
        performVMAction(vm, action: "suspend")
    }
    
//    NOTE: AFAIK, pause is synonymous with suspend...
//    @objc private func pauseVM(_ sender: NSMenuItem) {
//        guard let vm = sender.representedObject as? VMModel else { return }
//        performVMAction(vm, action: "pause")
//    }
    
    /// Resumes a paused/suspended VM by issuing "on" and then "unpause" actions.
    ///
    /// Some environments require both actions for a reliable resume.
    /// - Parameter sender: Menu item with `VMModel` in its representedObject.
    @objc private func unpauseVM(_ sender: NSMenuItem) {
        guard let vm = sender.representedObject as? VMModel else { return }
//        NOTE: Apparently the vm won't always resume with just "unpause"
        performVMAction(vm, action: "on")
        performVMAction(vm, action: "unpause")
    }
    
    /// Performs a power-related action on a VM via the REST API and refreshes the menu.
    ///
    /// - Parameters:
    ///   - vm: The VM on which to perform the action.
    ///   - action: The action string understood by the backend (e.g., "on", "off", "suspend").
    private func performVMAction(_ vm: VMModel, action: String) {
        guard let credentials = KeychainFactory.shared.getCredentials() else { return }
        let client = VMRestClient(username: credentials.username, password: credentials.password)
        
        client.performPowerAction(vmId: vm.id, action: action) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let state):
                print("VM \(vm.id) is now: \(state.powerState)")
                DispatchQueue.main.async { self.rebuildMenu() }
            case .failure:
                DispatchQueue.main.async {
                    AlertPresenter.show(messageText: "Action Failed",
                                        informativeText: "Failed to perform \(action) on \(vm.displayName ?? vm.id).")
                }
            }
        }
    }
    
    // MARK: - Permission prompts
    
    /// Prompts the user to select the folder containing `vmcli` and rebuilds the menu on completion.
    @objc private func promptForVMCLIFolder() {
        BookmarkManager.shared.promptUserToSelectVMCLIFolder { _ in
            DispatchQueue.main.async { self.rebuildMenu() }
        }
    }
    
    /// Prompts the user to grant access to a specific VM folder and rebuilds the menu on completion.
    /// - Parameter sender: The menu item whose representedObject is the VM's .vmx path.
    @objc private func promptForVMFolderFromMenu(_ sender: NSMenuItem) {
        guard let vmxPath = sender.representedObject as? String else { return }
        BookmarkManager.shared.promptUserToSelectVMFolder(for: vmxPath) { _ in
            DispatchQueue.main.async { self.rebuildMenu() }
        }
    }
}
