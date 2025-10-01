//
//  PreferencesWindowControllerUITests.swift
//  VMBarUITests
//
//  UI tests for PreferencesWindowController
//

import XCTest

class PreferencesWindowControllerUIWithVMRestTests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        continueAfterFailure = false
        app = XCUIApplication()
        
        app.launchArguments.append("--testing")
        
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
        
        // Wait for preferences window to appear
        let preferencesWindow = app.windows["Preferences"]
        XCTAssertTrue(preferencesWindow.waitForExistence(timeout: 3))
    }
}

// MARK: - Test Connection Button Tests

extension PreferencesWindowControllerUIWithVMRestTests {
    
    func testBadTestConnectionButtonBehavior() {
        openPreferences()
        
        let preferencesWindow = app.windows["Preferences"]
        let usernameField = preferencesWindow.textFields["usernameField"]
        let passwordField = preferencesWindow.secureTextFields["passwordField"]
        let testConnectionButton = preferencesWindow.buttons["testConnectionButton"]
        
        usernameField.doubleClick()
        usernameField.typeText("baduser")
        
        passwordField.doubleClick()
        passwordField.typeText("badpass")
        
        XCTAssertTrue(testConnectionButton.isEnabled)
        
        testConnectionButton.click()
        
        XCTAssertEqual(testConnectionButton.title, "Testing...")
        XCTAssertFalse(testConnectionButton.isEnabled)
        
        let alert = app.dialogs["alert"]
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        
        XCTAssertTrue(alert.staticTexts["Connection Failed"].exists)
        
        alert.buttons["OK"].click()
        
        XCTAssertEqual(testConnectionButton.title, "Test Connection")
        XCTAssertTrue(testConnectionButton.isEnabled)
    }
    
    func testGoodTestConnectionButtonBehavior() {
        openPreferences()
        
        let preferencesWindow = app.windows["Preferences"]
        let usernameField = preferencesWindow.textFields["usernameField"]
        let passwordField = preferencesWindow.secureTextFields["passwordField"]
        let testConnectionButton = preferencesWindow.buttons["testConnectionButton"]
        
        XCTAssertTrue(testConnectionButton.isEnabled)
        
//        NOTE: KeychainFactory doesn't work from within UI test, it's a separate process from the app...
//        let credentials = KeychainFactory.shared.getCredentials()
        
//        NOTE: Since we're storing the test credentials, we shouldn't need to load them here or set the fields.
//        let credentials = MockKeychainHelper().getCredentials()
//        usernameField.doubleClick()
//        usernameField.typeText(credentials?.username ?? "baduser")
//        
//        passwordField.doubleClick()
//        passwordField.typeText(credentials?.password ?? "badpass")
        
        XCTAssertTrue(testConnectionButton.isEnabled)
        
        testConnectionButton.click()
        
        XCTAssertEqual(testConnectionButton.title, "Testing...")
        XCTAssertFalse(testConnectionButton.isEnabled)
        
        let alert = app.dialogs["alert"]
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        
        XCTAssertTrue(alert.staticTexts["Connection Successful"].exists)
        
        alert.buttons["OK"].click()
        
        XCTAssertEqual(testConnectionButton.title, "Test Connection")
        XCTAssertTrue(testConnectionButton.isEnabled)
    }
}
