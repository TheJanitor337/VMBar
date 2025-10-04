//
//  PreferencesWindowController.swift
//  VMBar
//
//  Created by TJW on 9/21/25.
//

import Cocoa
import Network
import ServiceManagement

/// A window controller that manages the Preferences window for configuring
/// VMRest connection settings and app behavior.
/// 
/// Responsibilities:
/// - Load and persist host/port settings using `UserDefaults`.
/// - Store and retrieve credentials via `KeychainFactory`.
/// - Validate user input (host, port, username, password) with visual feedback.
/// - Enable/disable the "Test Connection" button based on validation state.
/// - Provide a way to test connectivity using `VMRestClient`.
class PreferencesWindowController: NSWindowController {
    
    // MARK: - Interface Builder Outlets
    
    /// Text field for the VMRest host (IP address or hostname).
    @IBOutlet weak var hostField: NSTextField!
    
    /// Text field for the VMRest port (1...65535).
    @IBOutlet weak var portField: NSTextField!
    
    /// Text field for the VMRest username.
    @IBOutlet weak var usernameField: NSTextField!
    
    /// Secure text field for the VMRest password.
    @IBOutlet weak var passwordField: NSSecureTextField!
    
    /// Checkbox to control whether the app starts at login.
    @IBOutlet weak var startAtLoginCheckbox: NSButton!
    
    /// Button to test connectivity to the VMRest endpoint with the provided credentials.
    @IBOutlet weak var testConnectionButton: NSButton!
    
    // MARK: - Dependencies and State
    
    /// User defaults store. Made injectable to facilitate testing.
    var defaults: UserDefaults = .standard
    
    /// Debounce timer used to delay validation while the user is typing.
    private var validationTimer: Timer?
    
    /// Validation state for the host field.
    /// Internal for test visibility.
    var isHostValid = false
    
    /// Validation state for the port field.
    /// Internal for test visibility.
    var isPortValid = false
    
    /// Validation state for the username field.
    /// Internal for test visibility.
    var isUsernameValid = false
    
    /// Validation state for the password field.
    /// Internal for test visibility.
    var isPasswordValid = false
    
    /// The name of the associated nib file for this window controller.
    override var windowNibName: NSNib.Name? {
        return "PreferencesWindowController"
    }
    
    /// Called after the window nib has been loaded.
    /// Sets up delegates, loads persisted values, performs initial validation,
    /// and updates the Test Connection button state.
    override func windowDidLoad() {
        super.windowDidLoad()
        
        setupFieldDelegates()
        setupWindowDelegate()
        loadSavedValues()
        validateAllFields()
        updateTestConnectionButtonState()
    }
    
    // MARK: - Setup
    
    /// Assigns self as the window's delegate to intercept close and lifecycle events.
    private func setupWindowDelegate() {
        window?.delegate = self
    }
    
    /// Assigns self as the delegate for all text fields to receive change/end-editing callbacks.
    private func setupFieldDelegates() {
        hostField.delegate = self
        portField.delegate = self
        usernameField.delegate = self
        passwordField.delegate = self
    }
    
    // MARK: - Loading and Persistence
    
    /// Loads saved values from `UserDefaults` and `KeychainFactory` into the UI.
    /// If no values are present, sensible defaults are applied.
    /// 
    /// - Note: Host defaults to `127.0.0.1` and port defaults to `8697`.
    /// - SeeAlso: `KeychainFactory.shared.getCredentials()`
    func loadSavedValues() {
        hostField.stringValue = defaults.string(forKey: "vmrestHost") ?? "127.0.0.1"
        portField.stringValue = defaults.string(forKey: "vmrestPort") ?? "8697"
        
        if let credentials = KeychainFactory.shared.getCredentials() {
            usernameField.stringValue = credentials.username
            passwordField.stringValue = credentials.password
        } else {
            usernameField.stringValue = ""
            passwordField.stringValue = ""
        }
        
        if #available(macOS 13.0, *) {
            let isEnabled = isLoginItemEnabled()
            startAtLoginCheckbox.state = isEnabled ? .on : .off
            defaults.set(isEnabled, forKey: "startAtLogin")
        } else {
            startAtLoginCheckbox.state = defaults.bool(forKey: "startAtLogin") ? .on : .off
        }
    }
    
    // MARK: - Validation Methods
    
    /// Validates the host string as either an IPv4/IPv6 address or a hostname.
    ///
    /// - Parameter host: The user-supplied host string (whitespace allowed).
    /// - Returns: `true` if the host is a valid IP or hostname; otherwise `false`.
    func validateHost(_ host: String) -> Bool {
        let trimmedHost = host.trimmingCharacters(in: .whitespaces)
        
        // Check if empty
        if trimmedHost.isEmpty {
            return false
        }
        
        // Check if it's a valid IP address or hostname
        return isValidIPAddress(trimmedHost) || isValidHostname(trimmedHost)
    }
    
    /// Validates the port string as an integer in the range 1...65535.
    ///
    /// - Parameter port: The user-supplied port string (whitespace allowed).
    /// - Returns: `true` if the port is within a valid range; otherwise `false`.
    func validatePort(_ port: String) -> Bool {
        let trimmedPort = port.trimmingCharacters(in: .whitespaces)
        
        // Check if it's a valid integer between 1 and 65535
        guard let portNumber = Int(trimmedPort),
              portNumber >= 1 && portNumber <= 65535 else {
            return false
        }
        
        return true
    }
    
    /// Validates the username.
    ///
    /// - Parameter username: The user-supplied username (whitespace allowed).
    /// - Returns: `true` if the username length is 1...255; otherwise `false`.
    func validateUsername(_ username: String) -> Bool {
        let trimmed = username.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && trimmed.count >= 1 && trimmed.count <= 255
    }
    
    /// Validates the password.
    ///
    /// - Parameter password: The user-supplied password (whitespace allowed).
    /// - Returns: `true` if the password length is 1...255; otherwise `false`.
    func validatePassword(_ password: String) -> Bool {
        return password.trimmingCharacters(in: .whitespaces).count > 0 && password.trimmingCharacters(in: .whitespaces).count <= 255 // Reasonable length limit
    }
    
    /// Determines whether a string is a valid IP address (IPv4 or IPv6).
    ///
    /// - Parameter string: The string to validate.
    /// - Returns: `true` if valid IPv4 or IPv6; otherwise `false`.
    func isValidIPAddress(_ string: String) -> Bool {
        // Check for IPv4
        if isValidIPv4(string) {
            return true
        }
        
        // Check for IPv6
        if isValidIPv6(string) {
            return true
        }
        
        return false
    }
    
    /// Validates that the provided string is a well-formed IPv4 address.
    ///
    /// - Important: This method rejects leading zeros (e.g., "01") to avoid ambiguity.
    /// - Parameter string: The candidate IPv4 string.
    /// - Returns: `true` if valid IPv4; otherwise `false`.
    func isValidIPv4(_ string: String) -> Bool {
        // Check for leading or trailing dots
        if string.hasPrefix(".") || string.hasSuffix(".") {
            return false
        }
        
        // Check for consecutive dots
        if string.contains("..") {
            return false
        }
        
        let components = string.split(separator: ".")
        
        // Must have exactly 4 components
        guard components.count == 4 else {
            return false
        }
        
        // Each component must be a valid number between 0-255
        for component in components {
            let componentStr = String(component)
            
            // Component cannot be empty
            if componentStr.isEmpty {
                return false
            }
            
            // Check for leading zeros (except "0" itself)
            if componentStr.count > 1 && componentStr.hasPrefix("0") {
                return false
            }
            
            // Must be a valid integer
            guard let num = Int(componentStr), num >= 0 && num <= 255 else {
                return false
            }
        }
        
        return true
    }
    
    /// Validates that the provided string is a well-formed IPv6 address.
    ///
    /// - Note: Uses `inet_pton` for canonical parsing and validation.
    /// - Parameter string: The candidate IPv6 string.
    /// - Returns: `true` if valid IPv6; otherwise `false`.
    func isValidIPv6(_ string: String) -> Bool {
        // Use inet_pton for IPv6 as it's more complex to validate manually
        var sin6 = sockaddr_in6()
        return string.withCString { cstring in
            return inet_pton(AF_INET6, cstring, &sin6.sin6_addr) == 1
        }
    }
    
    /// Validates that the provided string is a well-formed hostname.
    ///
    /// Rules enforced:
    /// - Maximum length 253 characters (practical limit from RFC 1035).
    /// - Labels (components) must be 1...63 characters.
    /// - Only letters, digits, and hyphens (LDH rule).
    /// - Labels cannot start or end with a hyphen.
    /// - No leading, trailing, or consecutive dots.
    /// - TLD must not be all numeric.
    ///
    /// - Parameter hostname: The candidate hostname string.
    /// - Returns: `true` if valid hostname; otherwise `false`.
    func isValidHostname(_ hostname: String) -> Bool {
        // If it looks like an IPv4 address (all numeric components), don't treat as hostname
        let components = hostname.split(separator: ".")
        if components.count == 4 && components.allSatisfy({ $0.allSatisfy(\.isNumber) }) {
            return false // This should be validated as an IP, not hostname
        }
        
        // Check overall length (RFC 1035: max 255 octets)
        guard hostname.count <= 253 && !components.isEmpty else {
            return false
        }
        
        // Must not start or end with a dot
        guard !hostname.hasPrefix(".") && !hostname.hasSuffix(".") else {
            return false
        }
        
        // Must not have consecutive dots
        guard !hostname.contains("..") else {
            return false
        }
        
        // Check each label according to LDH rule (RFC 3696)
        for component in components {
            let label = String(component)
            
            // Label length check (RFC 1035: max 63 octets per label)
            guard label.count >= 1 && label.count <= 63 else {
                return false
            }
            
            // LDH rule: only ASCII letters, digits, and hyphens
            guard label.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else {
                return false
            }
            
            // Hyphens not permitted at beginning or end of label
            guard !label.hasPrefix("-") && !label.hasSuffix("-") else {
                return false
            }
        }
        
        // Additional check: TLD (rightmost label) should not be all-numeric
        if let lastComponent = components.last {
            let tld = String(lastComponent)
            if tld.allSatisfy(\.isNumber) {
                return false
            }
        }
        
        return true
    }
    
    /// Validates all input fields and updates the UI to reflect their states.
    /// Updates the internal `is*Valid` flags and calls `updateFieldAppearance()`.
    func validateAllFields() {
        isHostValid = validateHost(hostField.stringValue)
        isPortValid = validatePort(portField.stringValue)
        isUsernameValid = validateUsername(usernameField.stringValue)
        isPasswordValid = validatePassword(passwordField.stringValue)
        
        updateFieldAppearance()
    }
    
    /// Applies background color changes to fields based on their validation state.
    /// Invalid fields receive a subtle red tint as visual feedback.
    private func updateFieldAppearance() {
        // Update field colors based on validation state
        hostField.backgroundColor = isHostValid ? NSColor.controlBackgroundColor : NSColor.systemRed.withAlphaComponent(0.1)
        portField.backgroundColor = isPortValid ? NSColor.controlBackgroundColor : NSColor.systemRed.withAlphaComponent(0.1)
        usernameField.backgroundColor = isUsernameValid ? NSColor.controlBackgroundColor : NSColor.systemRed.withAlphaComponent(0.1)
        passwordField.backgroundColor = isPasswordValid ? NSColor.controlBackgroundColor : NSColor.systemRed.withAlphaComponent(0.1)
    }
    
    /// Debounces validation while the user is typing to avoid excessive work and flicker.
    /// Schedules a one-shot timer that validates all fields and updates the Test button.
    private func scheduleValidation() {
        validationTimer?.invalidate()
        validationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
            self.validateAllFields()
            self.updateTestConnectionButtonState()
        }
    }
    
    // MARK: - Field Action Methods
    
    /// Called when the host field changes.
    /// Persists the host immediately if valid and schedules a validation pass.
    ///
    /// - Parameter sender: The host text field.
    @IBAction func hostChanged(_ sender: NSTextField) {
        let host = sender.stringValue.trimmingCharacters(in: .whitespaces)
        
        if validateHost(host) {
            defaults.set(host, forKey: "vmrestHost")
            isHostValid = true
        } else {
            isHostValid = false
        }
        
        scheduleValidation()
    }
    
    /// Called when the port field changes.
    /// Persists the port immediately if valid and schedules a validation pass.
    ///
    /// - Parameter sender: The port text field.
    @IBAction func portChanged(_ sender: NSTextField) {
        let port = sender.stringValue.trimmingCharacters(in: .whitespaces)
        
        if validatePort(port) {
            defaults.set(port, forKey: "vmrestPort")
            isPortValid = true
        } else {
            isPortValid = false
        }
        
        scheduleValidation()
    }
    
    /// Called when the username field changes.
    /// Saves credentials if both username and password are currently valid.
    ///
    /// - Parameter sender: The username text field.
    @IBAction func usernameChanged(_ sender: NSTextField) {
        isUsernameValid = validateUsername(sender.stringValue)
        
        if isUsernameValid && isPasswordValid {
            saveCredentials()
        }
        
        scheduleValidation()
    }
    
    /// Called when the password field changes.
    /// Saves credentials if both username and password are currently valid.
    ///
    /// - Parameter sender: The password secure text field.
    @IBAction func passwordChanged(_ sender: NSSecureTextField) {
        isPasswordValid = validatePassword(sender.stringValue)
        
        if isPasswordValid && isUsernameValid {
            saveCredentials()
        }
        
        scheduleValidation()
    }
    
    /// Called when the "Start at Login" checkbox changes.
    /// Updates both UserDefaults and the system login item registration.
    ///
    /// - Parameter sender: The checkbox button.
    @IBAction func startAtLoginChanged(_ sender: NSButton) {
        let shouldEnable = sender.state == .on
        defaults.set(shouldEnable, forKey: "startAtLogin")
        updateLoginItemStatus(shouldEnable)
    }
    
    // MARK: - Credential Management
    
    /// Attempts to save the current username and password to the Keychain.
    /// Shows a warning alert if saving fails.
    ///
    /// - Important: Username is trimmed for whitespace; password is stored as-is.
    /// - SeeAlso: `KeychainFactory.shared.saveCredentials(username:password:)`
    private func saveCredentials() {
        let username = usernameField.stringValue.trimmingCharacters(in: .whitespaces)
        let password = passwordField.stringValue
        
        if !username.isEmpty {
            let success = KeychainFactory.shared.saveCredentials(username: username, password: password)
            if !success {
                showAlert(title: "Warning", message: "Failed to save credentials to keychain.")
            }
        }
    }
    
    // MARK: - Start At Login
    
    /// Enables or disables the app as a login item using modern macOS APIs.
    ///
    /// - Parameter enabled: Whether to enable or disable login item status.
    /// - Returns: `true` if the operation succeeded; otherwise `false`.
    @available(macOS 13.0, *)
    private func setLoginItemEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            print("Failed to \(enabled ? "enable" : "disable") login item: \(error)")
            return false
        }
    }
    
    /// Retrieves the current login item status.
    ///
    /// - Returns: `true` if the app is registered as a login item; otherwise `false`.
    @available(macOS 13.0, *)
    private func isLoginItemEnabled() -> Bool {
        return SMAppService.mainApp.status == .enabled
    }

    /// Enables or disables the app as a login item, with fallback for older macOS versions.
    ///
    /// - Parameter enabled: Whether to enable or disable login item status.
    private func updateLoginItemStatus(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            let success = setLoginItemEnabled(enabled)
            if !success {
                // Revert checkbox on failure
                DispatchQueue.main.async {
                    self.startAtLoginCheckbox.state = enabled ? .off : .on
                    self.showAlert(
                        title: "Login Item Error",
                        message: "Failed to \(enabled ? "enable" : "disable") start at login. Please check System Settings > General > Login Items."
                    )
                }
            }
        } else {
            // For older macOS versions, show a message
            showAlert(
                title: "Not Supported",
                message: "Start at login requires macOS 13.0 or later."
            )
            // Revert checkbox
            DispatchQueue.main.async {
                self.startAtLoginCheckbox.state = .off
                self.defaults.set(false, forKey: "startAtLogin")
            }
        }
    }
    
    // MARK: - Connection Testing
    
    /// Tests connectivity to the configured VMRest endpoint using the provided credentials.
    ///
    /// Flow:
    /// 1. Validates host and port.
    /// 2. Validates username and password, saving credentials if valid.
    /// 3. Initializes `VMRestClient` and calls `testConnection`.
    /// 4. Presents an alert with the result and restores the button state.
    ///
    /// - Parameter sender: The "Test Connection" button.
    ///
    /// - Note: This method disables the button while testing and re-enables it afterward.
    /// - Warning: The initial validation here appears to call the wrong validators for host/port.
    ///            Consider changing `validateUsername(hostField.stringValue)` to `validateHost(...)`
    ///            and `validatePassword(portField.stringValue)` to `validatePort(...)`.
    /// - SeeAlso: `VMRestClient.testConnection(_:)`
    @IBAction func testConnectionTapped(_ sender: Any) {
//        TODO: Can this validation be done automatically when clicking button while editing one of these fields?
        isHostValid = validateUsername(hostField.stringValue)
        isPortValid = validatePassword(portField.stringValue)
        
        guard isHostValid && isPortValid else {
            showAlert(title: "Validation Error",
                     message: "Please fix the host and port fields before testing the connection.")
            return
        }
        
        let host = hostField.stringValue.trimmingCharacters(in: .whitespaces)
        let port = portField.stringValue.trimmingCharacters(in: .whitespaces)
        
        isUsernameValid = validateUsername(usernameField.stringValue)
        isPasswordValid = validatePassword(passwordField.stringValue)
        
        guard isUsernameValid && isPasswordValid else {
            showAlert(title: "Validation Error",
                     message: "Please fix the host and port fields before testing the connection.")
            return
        }
        
        saveCredentials()
        
        guard let credentials = KeychainFactory.shared.getCredentials() else {
            showAlert(title: "Missing Credentials",
                     message: "Please enter username and password before testing the connection.")
            return
        }

        let baseURL = "http://\(host):\(port)"
        let client = VMRestClient(baseURL: baseURL, username: credentials.username, password: credentials.password)

        testConnectionButton.isEnabled = false
        testConnectionButton.title = "Testing..."

        client.testConnection { success in
            DispatchQueue.main.async {
                
                let alert = NSAlert()
                alert.messageText = success ? "Connection Successful" : "Connection Failed"
                alert.informativeText = success ?
                    "VMRest API is reachable with the provided credentials." :
                    "Could not connect to VMRest API. Please check host, port, and credentials."
                alert.alertStyle = success ? .informational : .warning
                alert.runModal()
                
                self.testConnectionButton.isEnabled = true
                self.testConnectionButton.title = "Test Connection"
            }
        }
    }
    
    // MARK: - Window Closing Validation
    
    /// Validates all fields when the window is about to close and persists valid values.
    ///
    /// This method:
    /// - Ends editing for the current field to capture the latest value.
    /// - Validates all fields and aggregates error messages.
    /// - Presents an alert if there are issues, allowing the user to fix or discard changes.
    /// - Saves valid values to `UserDefaults`/Keychain.
    ///
    /// - Returns: `true` to allow the window to close; `false` to keep it open for corrections.
    func validateAndSaveAllFields() -> Bool {
        // Force end editing for the currently focused field
        window?.makeFirstResponder(nil)
        
        // Validate all fields
        validateAllFields()
        
        var hasErrors = false
        var errorMessages: [String] = []
        
        // Check each field and collect errors
        if !isHostValid {
            errorMessages.append("Host field contains an invalid IP address or hostname")
            hasErrors = true
        }
        
        if !isPortValid {
            errorMessages.append("Port must be a number between 1 and 65535")
            hasErrors = true
        }
        
        if !isUsernameValid && !usernameField.stringValue.trimmingCharacters(in: .whitespaces).isEmpty {
            errorMessages.append("Username is invalid")
            hasErrors = true
        }
        
        if !isPasswordValid {
            errorMessages.append("Password is too long (maximum 255 characters)")
            hasErrors = true
        }
        
        // If there are errors, show them and prevent closing
        if hasErrors {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Invalid Field Values"
            alert.informativeText = "Please fix the following issues:\n\n• " + errorMessages.joined(separator: "\n• ")
            alert.addButton(withTitle: "Fix Issues")
            alert.addButton(withTitle: "Discard Changes")
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                return false // Don't close, let user fix issues
            } else {
                // User chose to discard changes - reload original values
                loadSavedValues()
                validateAllFields()
                return true // Allow closing
            }
        }
        
        // No errors - save valid values
        if isHostValid {
            let host = hostField.stringValue.trimmingCharacters(in: .whitespaces)
            defaults.set(host, forKey: "vmrestHost")
        }
        
        if isPortValid {
            let port = portField.stringValue.trimmingCharacters(in: .whitespaces)
            defaults.set(port, forKey: "vmrestPort")
        }
        
        if isUsernameValid && isPasswordValid {
            saveCredentials()
        }
        
        return true
    }
    
    // MARK: - Helper Methods
    
    /// Enables or disables the "Test Connection" button based on current validation state.
    ///
    /// Conditions:
    /// - Host, port, and username must be valid.
    /// - Username must be non-empty (credentials present).
    func updateTestConnectionButtonState() {
        let hasValidFields = isHostValid && isPortValid && isUsernameValid
        let hasCredentials = !usernameField.stringValue.trimmingCharacters(in: .whitespaces).isEmpty
        
        testConnectionButton.isEnabled = hasValidFields && hasCredentials
    }
    
    /// Presents a simple informational alert with a single "OK" button.
    ///
    /// - Parameters:
    ///   - title: The alert's title.
    ///   - message: The informative text for the alert.
    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    // MARK: - Cleanup
    
    /// Invalidates any scheduled validation timer upon deallocation.
    deinit {
        validationTimer?.invalidate()
    }
}

// MARK: - NSWindowDelegate

extension PreferencesWindowController: NSWindowDelegate {
    
    /// Asks the delegate whether the window should close.
    ///
    /// - Parameter sender: The window attempting to close.
    /// - Returns: `true` if closing is allowed; otherwise `false`.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        return validateAndSaveAllFields()
    }
    
    /// Notifies the delegate that the window is about to close.
    /// Performs final cleanup by invalidating the validation timer.
    ///
    /// - Parameter notification: The close notification.
    func windowWillClose(_ notification: Notification) {
        // Final cleanup - invalidate timers
        validationTimer?.invalidate()
        validationTimer = nil
    }
}

// MARK: - NSTextFieldDelegate

extension PreferencesWindowController: NSTextFieldDelegate {
    
    /// Called when the text of a control changes.
    /// Updates the corresponding validation state and schedules a debounce validation pass.
    ///
    /// - Parameter obj: The notification containing the text field.
    func controlTextDidChange(_ obj: Notification) {
        guard let textField = obj.object as? NSTextField else { return }
        
        // Trigger validation for the specific field
        switch textField {
        case hostField:
            isHostValid = validateHost(textField.stringValue)
        case portField:
            isPortValid = validatePort(textField.stringValue)
        case usernameField:
            isUsernameValid = validateUsername(textField.stringValue)
        case passwordField:
            isPasswordValid = validatePassword(textField.stringValue)
        default:
            break
        }
        
        scheduleValidation()
    }
    
    /// Called when editing ends for a text field.
    /// Persists valid values immediately to `UserDefaults` or Keychain.
    ///
    /// - Parameter obj: The notification containing the text field.
    func controlTextDidEndEditing(_ obj: Notification) {
        guard let textField = obj.object as? NSTextField else { return }
        
        // Save valid values when editing ends
        switch textField {
        case hostField:
            if isHostValid {
                let host = textField.stringValue.trimmingCharacters(in: .whitespaces)
                defaults.set(host, forKey: "vmrestHost")
            }
        case portField:
            if isPortValid {
                let port = textField.stringValue.trimmingCharacters(in: .whitespaces)
                defaults.set(port, forKey: "vmrestPort")
            }
        case usernameField, passwordField:
            if isUsernameValid && isPasswordValid {
                saveCredentials()
            }
        default:
            break
        }
    }
}

