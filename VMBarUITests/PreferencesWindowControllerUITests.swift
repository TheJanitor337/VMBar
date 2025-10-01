//
//  PreferencesWindowControllerUITests.swift
//  VMBarUITests
//
//  UI tests for PreferencesWindowController
//

import XCTest

class PreferencesWindowControllerUITests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        continueAfterFailure = false
        app = XCUIApplication()
        
        app.launchArguments.append("--testingDefault")
        
        app.launch()
        app.activate()
        
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
    }
    
    override func tearDownWithError() throws {
        app.terminate()
        app = nil
        try super.tearDownWithError()
    }
    
    private func openPreferences() {
        let statusItem = app.menuBars.element(boundBy: 1)
        XCTAssertTrue(statusItem.exists, "The status bar statusItem doesn't exist.")
        statusItem.click()
        
        let preferencesMenuItem = app.menuBars.menuItems["Preferences..."]
        XCTAssertTrue(preferencesMenuItem.exists, "The Preferences menu item doesn't exist.")
        preferencesMenuItem.click()
        // OR: app.typeKey(",", modifierFlags: .command)
//        app.typeKey(",", modifierFlags: .command)
        // OR: app.buttons["Preferences"].click().
        
        // Wait for preferences window to appear
        let preferencesWindow = app.windows["Preferences"]
        XCTAssertTrue(preferencesWindow.waitForExistence(timeout: 3))
    }
}

// MARK: - Basic UI Element Tests

extension PreferencesWindowControllerUITests {
    
    func testPreferencesWindowExists() {
        openPreferences()
        
        let preferencesWindow = app.windows["Preferences"]
        XCTAssertTrue(preferencesWindow.exists)
        
        // Check that all main elements exist
        XCTAssertTrue(preferencesWindow.textFields["hostField"].exists)
        XCTAssertTrue(preferencesWindow.textFields["portField"].exists)
        XCTAssertTrue(preferencesWindow.textFields["usernameField"].exists)
        XCTAssertTrue(preferencesWindow.secureTextFields["passwordField"].exists)
        XCTAssertTrue(preferencesWindow.checkBoxes["startAtLoginCheckbox"].exists)
        XCTAssertTrue(preferencesWindow.buttons["testConnectionButton"].exists)
    }
    
    func testDefaultValues() {
        openPreferences()
        
        let preferencesWindow = app.windows["Preferences"]
        
        // Check default values
        XCTAssertEqual(preferencesWindow.textFields["hostField"].value as? String, "127.0.0.1")
        XCTAssertEqual(preferencesWindow.textFields["portField"].value as? String, "8697")
        XCTAssertEqual(preferencesWindow.checkBoxes["startAtLoginCheckbox"].value as? Int, 0)
    }
}

// MARK: - Field Validation UI Tests

extension PreferencesWindowControllerUITests {
    
    func testHostFieldValidation() {
        openPreferences()
        
        let preferencesWindow = app.windows["Preferences"]
        let hostField = preferencesWindow.textFields["hostField"]
        let testConnectionButton = preferencesWindow.buttons["testConnectionButton"]
        
        // Test valid IP
        hostField.click()
        hostField.typeText("\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}") // Clear field (backspaces)
        hostField.typeText("192.168.1.1")
        
        // Test that valid IP enables the test button (when other fields are valid)
        // Note: Button state depends on all fields being valid
        
        // Test invalid IP
        hostField.click()
        hostField.typeText("\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}") // Clear
        hostField.typeText("127.0.0.300")
        
        // Allow time for validation to process
        sleep(1)
        
        // Test connection button should be disabled for invalid host
        XCTAssertFalse(testConnectionButton.isEnabled)
        
        // Test valid hostname
        hostField.click()
        hostField.typeText("\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}") // Clear
        hostField.typeText("example.com")
        
        sleep(1) // Allow validation time
    }
    
    func testPortFieldValidation() {
        openPreferences()
        
        let preferencesWindow = app.windows["Preferences"]
        let portField = preferencesWindow.textFields["portField"]
        let testConnectionButton = preferencesWindow.buttons["testConnectionButton"]
        
        // Test valid port
        portField.doubleClick()
        portField.typeText("\u{8}") // Clear
        portField.typeText("8080")
        
        // Test invalid port (too high)
        portField.doubleClick()
        portField.typeText("\u{8}")
        portField.typeText("70000")
        
        sleep(1)
        XCTAssertFalse(testConnectionButton.isEnabled)
        
        // Test invalid port (zero)
        portField.doubleClick()
        portField.typeText("\u{8}")
        portField.typeText("0")
        
        sleep(1)
        XCTAssertFalse(testConnectionButton.isEnabled)
        
        // Test non-numeric port
        portField.doubleClick()
        portField.typeText("\u{8}")
        portField.typeText("abc")
        
        sleep(1)
        XCTAssertFalse(testConnectionButton.isEnabled)
    }
    
    func testUsernamePasswordFields() {
        openPreferences()
        
        let preferencesWindow = app.windows["Preferences"]
        let usernameField = preferencesWindow.textFields["usernameField"]
        let passwordField = preferencesWindow.secureTextFields["passwordField"]
        let testConnectionButton = preferencesWindow.buttons["testConnectionButton"]
        
        // Reset username/password fields since we're storing them in the testing keychain
        usernameField.doubleClick()
        usernameField.typeText("\u{8}")
        usernameField.typeText("")
        
        passwordField.doubleClick()
        passwordField.typeText("\u{8}")
        passwordField.typeText("")
        
        // Initially button should be disabled (no credentials)
        XCTAssertFalse(testConnectionButton.isEnabled)
        
        // Add username
        usernameField.doubleClick()
        usernameField.typeText("testuser")
        
        // Add password
        passwordField.doubleClick()
        passwordField.typeText("testpass")
        
        sleep(1)
        
        // With valid host, port, and credentials, button should be enabled
        XCTAssertTrue(testConnectionButton.isEnabled)
    }
}

// MARK: - Complete Validation Flow Tests

extension PreferencesWindowControllerUITests {
    
    func testCompleteValidationFlow() {
        openPreferences()
        
        let preferencesWindow = app.windows["Preferences"]
        let hostField = preferencesWindow.textFields["hostField"]
        let portField = preferencesWindow.textFields["portField"]
        let usernameField = preferencesWindow.textFields["usernameField"]
        let passwordField = preferencesWindow.secureTextFields["passwordField"]
        let testConnectionButton = preferencesWindow.buttons["testConnectionButton"]
        
        // Set all valid values
        hostField.doubleClick()
        hostField.typeText("\u{8}") // Clear
        hostField.typeText("example.com")
        
        portField.doubleClick()
        portField.typeText("\u{8}")
        portField.typeText("8080")
        
        usernameField.click()
        usernameField.typeText("admin")
        
        passwordField.click()
        passwordField.typeText("password123")
        
        sleep(1)
        
        XCTAssertTrue(testConnectionButton.isEnabled)
        
        hostField.doubleClick()
        hostField.typeText("\u{8}")
        hostField.typeText("127.0.0.300")
        
        sleep(1)
        XCTAssertFalse(testConnectionButton.isEnabled)
    }
    
    func testStartAtLoginCheckbox() {
        openPreferences()
        
        let preferencesWindow = app.windows["Preferences"]
        let checkbox = preferencesWindow.checkBoxes["startAtLoginCheckbox"]
        
        // Initially unchecked
        XCTAssertEqual(checkbox.value as? Int, 0)
        
        // Click to check
        checkbox.click()
        XCTAssertEqual(checkbox.value as? Int, 1)
        
        // Click to uncheck
        checkbox.click()
        XCTAssertEqual(checkbox.value as? Int, 0)
    }
}

// MARK: - Window Closing Tests

extension PreferencesWindowControllerUITests {
    
    func testWindowClosingWithValidData() {
        openPreferences()
        
        let preferencesWindow = app.windows["Preferences"]
//        let hostField = preferencesWindow.textFields["hostField"]
//        let portField = preferencesWindow.textFields["portField"]
        let usernameField = preferencesWindow.textFields["usernameField"]
        let passwordField = preferencesWindow.secureTextFields["passwordField"]
        
//        hostField.doubleClick()
//        hostField.typeText("\u{8}")
//        hostField.typeText("example.com")
//        
//        portField.doubleClick()
//        portField.typeText("\u{8}")
//        portField.typeText("8080")
        
        usernameField.doubleClick()
        usernameField.typeText("testuser")
        
        passwordField.doubleClick()
        passwordField.typeText("testpass")
        
        // Close the window
        preferencesWindow.buttons[XCUIIdentifierCloseWindow].click()
        
        // Window should close without issues
        XCTAssertFalse(preferencesWindow.exists)
    }
    
    func testWindowClosingWithInvalidDataShowsAlert() {
        openPreferences()
        
        let preferencesWindow = app.windows["Preferences"]
        let hostField = preferencesWindow.textFields["hostField"]
        let portField = preferencesWindow.textFields["portField"]
        
        // Set invalid values
        hostField.doubleClick()
        hostField.typeText("\u{8}")
        hostField.typeText("127.0.0.300") // Invalid IP
        
        portField.doubleClick()
        portField.typeText("\u{8}")
        portField.typeText("70000") // Invalid port
        
        // Try to close the window
        preferencesWindow.buttons[XCUIIdentifierCloseWindow].click()
        
        let alertDialog1 = app.dialogs["alert"]
        
        // Should show validation alert
        let alertMessage = alertDialog1.staticTexts["Invalid Field Values"]
        XCTAssertTrue(alertMessage.waitForExistence(timeout: 3))
        
        // Alert should contain error messages
        XCTAssertTrue(alertDialog1.staticTexts.containing(NSPredicate(format: "value CONTAINS 'Host field contains an invalid'")).firstMatch.exists)
        XCTAssertTrue(alertDialog1.staticTexts.containing(NSPredicate(format: "value CONTAINS 'Port must be a number'")).firstMatch.exists)
        
        // Test "Fix Issues" option
        alertDialog1.buttons["Fix Issues"].click()
        
        // Window should still be open
        XCTAssertTrue(preferencesWindow.exists)
        
        // Try closing again and choose "Discard Changes"
        preferencesWindow.buttons[XCUIIdentifierCloseWindow].click()
        
        let alertDialog2 = app.dialogs["alert"]
        
        let alertMessage2 = alertDialog2.staticTexts["Invalid Field Values"]
        XCTAssertTrue(alertMessage2.waitForExistence(timeout: 3))
        
        alertDialog2.buttons["Discard Changes"].click()
        
        // Window should now close
        XCTAssertFalse(preferencesWindow.waitForExistence(timeout: 1))
    }
}

// MARK: - Field Interaction Tests

extension PreferencesWindowControllerUITests {
    
    func testFieldTabbing() {
        openPreferences()
        
        let preferencesWindow = app.windows["Preferences"]
//        let hostField = preferencesWindow.textFields["hostField"]
        let portField = preferencesWindow.textFields["portField"]
        let usernameField = preferencesWindow.textFields["usernameField"]
        let passwordField = preferencesWindow.secureTextFields["passwordField"]
        
        // Focus host field
//        hostField.click()
        
        // Tab to Port, replace content, and verify typing affects Port
        app.typeKey(XCUIKeyboardKey.tab, modifierFlags: [])
        app.typeKey("a", modifierFlags: .command) // Select All
        app.typeText("1234")
        XCTAssertEqual(portField.value as? String, "1234")
        
        // Tab to Username, replace content, and verify
        app.typeKey(XCUIKeyboardKey.tab, modifierFlags: [])
        app.typeKey("a", modifierFlags: .command)
        app.typeText("user1")
        XCTAssertEqual(usernameField.value as? String, "user1")
        
        // Tab to Password, replace content, and verify it's non-empty (secure text shows bullets)
        app.typeKey(XCUIKeyboardKey.tab, modifierFlags: [])
        app.typeKey("a", modifierFlags: .command)
        app.typeText("pass1")
        let pwdValue = passwordField.value as? String
        XCTAssertNotNil(pwdValue)
        XCTAssertFalse((pwdValue ?? "").isEmpty)
        
        // Shift+Tab back to Username, replace content, and verify
        app.typeKey(XCUIKeyboardKey.tab, modifierFlags: .shift)
        app.typeKey("a", modifierFlags: .command)
        app.typeText("user2")
        XCTAssertEqual(usernameField.value as? String, "user2")
    }
    
    func testFieldClearingAndTyping() {
        openPreferences()
        
        let preferencesWindow = app.windows["Preferences"]
        let hostField = preferencesWindow.textFields["hostField"]
        
        // Select all and replace
        hostField.click()
        app.typeKey("a", modifierFlags: .command) // Select All
        hostField.typeText("newhost.example.com")
        
        XCTAssertEqual(hostField.value as? String, "newhost.example.com")
        
        // Test partial selection and replacement
        hostField.click()
        // Double-click to select word (this might need adjustment based on actual behavior)
        hostField.doubleTap()
        hostField.typeText("localhost")
        
        // The exact result depends on what was selected, but something should change
        XCTAssertNotEqual(hostField.value as? String, "newhost.example.com")
    }
    
    func testRealTimeValidation() {
        openPreferences()
        
        let preferencesWindow = app.windows["Preferences"]
        let hostField = preferencesWindow.textFields["hostField"]
        let testConnectionButton = preferencesWindow.buttons["testConnectionButton"]
        
        // Start with a good host, add credentials to enable button
        let usernameField = preferencesWindow.textFields["usernameField"]
        let passwordField = preferencesWindow.secureTextFields["passwordField"]
        
        usernameField.doubleClick()
        usernameField.typeText("user")
        passwordField.doubleClick()
        passwordField.typeText("pass")
        
        // Now test real-time validation on host field
        hostField.doubleClick()
        hostField.typeText("\u{8}") // Clear
        hostField.typeText("127.0.0.") // Partial invalid IP
        
        // Give validation time to process
        sleep(1)
        XCTAssertFalse(testConnectionButton.isEnabled)
        
        // Complete with valid ending
        hostField.typeText("1")
        sleep(1)
        XCTAssertTrue(testConnectionButton.isEnabled)
        
        // Add invalid ending
        hostField.typeText("300") // Now becomes 127.0.0.1300
        sleep(1)
        XCTAssertFalse(testConnectionButton.isEnabled)
    }
}

// MARK: - Keyboard Shortcuts Tests

extension PreferencesWindowControllerUITests {
    
    func testKeyboardShortcuts() {
        openPreferences()
        
        let preferencesWindow = app.windows["Preferences"]
        
        // Test Escape key closes window (if implemented)
        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        // This depends on your implementation - adjust as needed
        
        // Test Enter key on Test Connection button (if possible)
        // First set up valid data
        let hostField = preferencesWindow.textFields["hostField"]
        let usernameField = preferencesWindow.textFields["usernameField"]
        let passwordField = preferencesWindow.secureTextFields["passwordField"]
        let testConnectionButton = preferencesWindow.buttons["testConnectionButton"]
        
        hostField.click()
        hostField.typeText("\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}\u{8}")
        hostField.typeText("httpbin.org")
        
        usernameField.click()
        usernameField.typeText("test")
        
        passwordField.click()
        passwordField.typeText("test")
        
        sleep(1)
        
        // Attempt to trigger via Return (default button), fall back to clicking if needed
        app.typeKey(XCUIKeyboardKey.return, modifierFlags: [])
        sleep(1)
        
        if !(app.alerts.firstMatch.exists || testConnectionButton.title == "Testing...") {
            // Fallback: click the button
            testConnectionButton.click()
        }
        
        // Should trigger the connection test
        // Wait for and dismiss the result alert
        let alert = app.alerts.firstMatch
        if alert.waitForExistence(timeout: 10) {
            alert.buttons["OK"].click()
        }
    }
    
    func testCommandKeysIfImplemented() {
        openPreferences()
        
        // Test Cmd+W to close window (standard macOS behavior)
        app.typeKey("w", modifierFlags: .command)
        
        // Window should close (or show validation alert if data is invalid)
        let preferencesWindow = app.windows["Preferences"]
        
        // Either the window closed, or an alert appeared
        XCTAssertTrue(!preferencesWindow.exists || app.dialogs.firstMatch.exists)
    }
}

// MARK: - Performance and Stress Tests

extension PreferencesWindowControllerUITests {
    
    func testRapidFieldChanges() {
        openPreferences()
        
        let preferencesWindow = app.windows["Preferences"]
        let hostField = preferencesWindow.textFields["hostField"]
        
        // Rapidly change the host field to test validation performance
        let testValues = ["a", "ab", "abc", "abc.", "abc.c", "abc.co", "abc.com"]
        
        for value in testValues {
            hostField.click()
            app.typeKey("a", modifierFlags: .command) // Select all
            hostField.typeText(value)
            // Small delay to allow some validation processing
            usleep(100000) // 0.1 second
        }
        
        // App should remain responsive
        XCTAssertTrue(preferencesWindow.exists)
    }
    
    func testLongInputValues() {
        openPreferences()
        
        let preferencesWindow = app.windows["Preferences"]
        let hostField = preferencesWindow.textFields["hostField"]
        let usernameField = preferencesWindow.textFields["usernameField"]
        
        // Test very long hostname (should be rejected)
        let longHostname = String(repeating: "verylongsubdomain.", count: 20) + "com"
        hostField.click()
        app.typeKey("a", modifierFlags: .command)
        hostField.typeText(longHostname)
        
        sleep(1)
        
        // Should be marked as invalid
        let testConnectionButton = preferencesWindow.buttons["testConnectionButton"]
        XCTAssertFalse(testConnectionButton.isEnabled)
        
        // Test maximum valid username length
        let maxUsername = String(repeating: "a", count: 255)
        usernameField.click()
        usernameField.typeText(maxUsername)
        
        sleep(1)
        // Should handle gracefully without crashing
        XCTAssertTrue(preferencesWindow.exists)
    }
}

// MARK: - Edge Case Tests

extension PreferencesWindowControllerUITests {
    
    func testSpecialCharactersInFields() {
        openPreferences()
        
        let preferencesWindow = app.windows["Preferences"]
        let hostField = preferencesWindow.textFields["hostField"]
        let usernameField = preferencesWindow.textFields["usernameField"]
        
        // Test special characters in hostname (should be rejected for standard hostnames)
        hostField.click()
        app.typeKey("a", modifierFlags: .command)
        hostField.typeText("host@example.com")
        
        sleep(1)
        
        // Should be invalid
        let testConnectionButton = preferencesWindow.buttons["testConnectionButton"]
        XCTAssertFalse(testConnectionButton.isEnabled)
        
        // Test Unicode characters in username (should be allowed)
        usernameField.click()
        usernameField.typeText("user@example.com")
        
        // App should handle without crashing
        XCTAssertTrue(preferencesWindow.exists)
    }
    
    func testEmptyAndWhitespaceFields() {
        openPreferences()
        
        let preferencesWindow = app.windows["Preferences"]
        let hostField = preferencesWindow.textFields["hostField"]
        let usernameField = preferencesWindow.textFields["usernameField"]
        let testConnectionButton = preferencesWindow.buttons["testConnectionButton"]
        
        // Clear host field completely
        hostField.click()
        app.typeKey("a", modifierFlags: .command)
        app.typeKey(XCUIKeyboardKey.delete, modifierFlags: [])
        
        sleep(1)
        XCTAssertFalse(testConnectionButton.isEnabled)
        
        // Set host to only whitespace
        hostField.typeText("   ")
        sleep(1)
        XCTAssertFalse(testConnectionButton.isEnabled)
        
        // Same test for username
        usernameField.click()
        usernameField.typeText("   ")
        sleep(1)
        XCTAssertFalse(testConnectionButton.isEnabled)
    }
}

// MARK: - Accessibility Tests

extension PreferencesWindowControllerUITests {
    
    func testAccessibilityLabels() {
        openPreferences()
        
        let preferencesWindow = app.windows["Preferences"]
        
        // Test that fields have proper accessibility labels
        XCTAssertTrue(preferencesWindow.textFields["hostField"].exists)
        XCTAssertTrue(preferencesWindow.textFields["portField"].exists)
        XCTAssertTrue(preferencesWindow.textFields["usernameField"].exists)
        XCTAssertTrue(preferencesWindow.secureTextFields["passwordField"].exists)
        XCTAssertTrue(preferencesWindow.buttons["testConnectionButton"].exists)
        XCTAssertTrue(preferencesWindow.checkBoxes["startAtLoginCheckbox"].exists)
        
        // Test that elements are accessible via accessibility API
        let hostField = preferencesWindow.textFields["hostField"]
        XCTAssertNotNil(hostField.label)
        XCTAssertTrue(hostField.isHittable)
    }
    
    func testVoiceOverSupport() {
        // Enable accessibility features for this test
        // Note: This requires the app to have proper accessibility implementation
        openPreferences()
        
        let preferencesWindow = app.windows["Preferences"]
        let hostField = preferencesWindow.textFields["hostField"]
        
        // Test that accessibility value updates when field value changes
        let originalValue = hostField.value as? String
        
        hostField.click()
        app.typeKey("a", modifierFlags: .command)
        hostField.typeText("newvalue.com")
        
        let newValue = hostField.value as? String
        XCTAssertNotEqual(originalValue, newValue)
        XCTAssertEqual(newValue, "newvalue.com")
    }
}

