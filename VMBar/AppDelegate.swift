//
//  AppDelegate.swift
//  VMBar
//
//  Created by TJW on 9/21/25.
//

import Cocoa

/// The application delegate for the macOS app.
///
/// Responsibilities:
/// - Bootstraps the application on launch.
/// - Registers default preferences from `defaultPrefs.plist`.
/// - Creates and manages the status bar menu via `VMMenuController`.
/// - Presents the Preferences window via `PreferencesWindowController`.
/// - Provides a deterministic testing hook (`--testing`) to reset user defaults.
///
/// Notes:
/// - This app is designed to run primarily from the menu bar; there is no main window.
/// - The `--testing` command-line flag enables a clean state by resetting UserDefaults.
class AppDelegate: NSObject, NSApplicationDelegate {
    /// The controller that manages the menu bar status item and its menu.
    private var menuController: VMMenuController!
    
    /// Lazily created window controller for the Preferences window.
    /// Created the first time preferences are opened and retained for reuse.
    var preferencesWindowController: PreferencesWindowController?

    /// Called after the app has been launched and initialized.
    ///
    /// Behavior:
    /// - If launched with the `--testing` flag, resets all user defaults to a known state.
    /// - Registers default preferences from `defaultPrefs.plist`.
    /// - Instantiates and starts the `VMMenuController` to create the status bar menu.
    ///
    /// - Parameter aNotification: The launch notification provided by AppKit.
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        if CommandLine.arguments.contains("--testing") {
            testSetup()
        }
        
        registerDefaultPreferences()
        
        // Create and start the menu controller
        menuController = VMMenuController(openPreferences: { [weak self] in
            self?.openPreferences()
        })
        menuController.start()
    }
    
    // MARK: - Process commandline arguments
    
    /// Performs setup steps used when running in testing mode.
    ///
    /// Currently resets UserDefaults to ensure a clean and deterministic environment.
    /// Triggered by launching the app with the `--testing` command-line argument.
    func testSetup() {
        resetDefaults()
    }
    
    // MARK: - Register default preferences
    
    /// Loads and registers default preferences from `defaultPrefs.plist`.
    ///
    /// This does not overwrite existing user-set values; it only provides fallback defaults
    /// for keys that have not yet been set.
    ///
    /// If `defaultPrefs.plist` cannot be loaded or parsed, the method logs a failure message
    /// and leaves existing defaults unchanged.
    func registerDefaultPreferences() {
        guard
            let url = Bundle.main.url(forResource: "defaultPrefs", withExtension: "plist"),
            let data = try? Data(contentsOf: url),
            let defaultPreferences = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        else {
            print("Failed to load default preferences")
            return
        }

        UserDefaults.standard.register(defaults: defaultPreferences)
    }

    // MARK: - Preferences

    /// Opens the Preferences window, creating it if necessary.
    ///
    /// The window is made key and brought to the front. If the window controller has not been
    /// created yet, it is instantiated and retained for subsequent uses.
    @objc func openPreferences() {
        if preferencesWindowController == nil {
            preferencesWindowController = PreferencesWindowController()
        }
        preferencesWindowController?.showWindow(nil)
        preferencesWindowController?.window?.makeKeyAndOrderFront(nil)
    }
    
    // MARK: - Testing Teardown
    
    /// Resets all stored user defaults to a clean state and re-registers defaults.
    ///
    /// Steps:
    /// - Removes the persistent domain for this app's bundle identifier, clearing all keys.
    /// - Reloads default values from `defaultPrefs.plist` and registers them.
    /// - Calls `synchronize()` to ensure changes are written promptly (useful for tests).
    ///
    /// This method is intended for testing scenarios and should not be used during normal runtime.
    /// If `defaultPrefs.plist` is missing or invalid, the method logs an error and terminates
    /// the application via `fatalError` to avoid running in an undefined state during tests.
    private func resetDefaults() {
        let defaults = UserDefaults.standard
        let domain = Bundle.main.bundleIdentifier!
        defaults.removePersistentDomain(forName: domain)
        
        guard
            let url = Bundle.main.url(forResource: "defaultPrefs", withExtension: "plist"),
            let data = try? Data(contentsOf: url),
            let defaultPreferences = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        else {
            print("Error: defaultPrefs.plist is missing or corrupted.")
            fatalError("Critical failure: Unable to reset to default preferences.")
        }

        defaults.register(defaults: defaultPreferences)
        // Note: synchronize() is generally unnecessary in modern macOS; it is used here to
        // make preference writes deterministic in testing scenarios.
        defaults.synchronize()
    }
}

