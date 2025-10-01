//
//  PreferencesWindowControllerTests.swift
//  VMBarTests
//
//  Unit tests for PreferencesWindowController
//

import XCTest
import AppKit
@testable import VMBar

class PreferencesWindowControllerTests: XCTestCase {
    
    var preferencesController: PreferencesWindowController!
    var mockDefaults: UserDefaults!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        setenv("VMBarTesting", "1", 1)
        
        // Create a mock UserDefaults for testing
        mockDefaults = UserDefaults(suiteName: "test.preferences")
        mockDefaults.removePersistentDomain(forName: "test.preferences")
        
        mockDefaults.set(false, forKey: "startAtLogin")
        mockDefaults.set("127.0.0.1", forKey: "vmrestHost")
        mockDefaults.set("8697", forKey: "vmrestPort")
        
        // Create the preferences controller
        preferencesController = PreferencesWindowController()
        
        // Replace the real defaults with our mock
        preferencesController.defaults = mockDefaults
        
        // Load the window to initialize outlets
        _ = preferencesController.window
        preferencesController.windowDidLoad()
    }
    
    override func tearDownWithError() throws {
        unsetenv("VMBarTesting")
        preferencesController = nil
        mockDefaults.removePersistentDomain(forName: "test.preferences")
        mockDefaults = nil
        try super.tearDownWithError()
    }
}

// MARK: - IPv4 Validation Tests

extension PreferencesWindowControllerTests {
    
    func testValidIPv4Addresses() {
        let validIPs = [
            "127.0.0.1",
            "192.168.1.1",
            "10.0.0.1",
            "255.255.255.255",
            "0.0.0.0",
            "172.16.0.1",
            "8.8.8.8"
        ]
        
        for ip in validIPs {
            let result = preferencesController.isValidIPv4(ip)
            XCTAssertTrue(result, "Should validate \(ip) as valid IPv4")
        }
    }
    
    func testInvalidIPv4Addresses() {
        let invalidIPs = [
            "127.0.0.256",     // Octet > 255
            "127.0.0.300",     // Octet > 255
            "127.0.0",         // Too few octets
            "127.0.0.1.1",     // Too many octets
            "127.001.0.1",     // Leading zero
            "127.-1.0.1",      // Negative number
            "127.0.0.",        // Trailing dot
            ".127.0.0.1",      // Leading dot
            "127..0.1",        // Double dot
            "abc.0.0.1",       // Non-numeric
            "",                // Empty string
            "999.999.999.999"  // All octets > 255
        ]
        
        for ip in invalidIPs {
            let result = preferencesController.isValidIPv4(ip)
            XCTAssertFalse(result, "Should validate \(ip) as invalid IPv4")
        }
    }
}

// MARK: - Hostname Validation Tests

extension PreferencesWindowControllerTests {
    
    func testValidHostnames() {
        let validHostnames = [
            "localhost",
            "example.com",
            "sub-domain.example.com",
            "test123.example-site.org",
            "a.b.c.d.example.com",
            "my-server.local",
            "server1.internal",
            "web-01.prod.company.net"
        ]
        
        for hostname in validHostnames {
            let result = preferencesController.isValidHostname(hostname)
            XCTAssertTrue(result, "Should validate \(hostname) as valid hostname")
        }
    }
    
    func testInvalidHostnames() {
        let invalidHostnames = [
            "127.0.0.1",         // IP address (should be validated as IP)
            "192.168.1.1",       // IP address
            "127.0.0.300",       // Malformed IP (all numeric components)
            "-example.com",      // Starts with hyphen
            "example-.com",      // Ends with hyphen
            "example..com",      // Double dot
            ".example.com",      // Starts with dot
            "example.com.",      // Ends with dot
            "example.123",       // All-numeric TLD
            "example.c_m",       // Underscore not allowed
            "exam ple.com",      // Space not allowed
            "example.c@m",       // Special character not allowed
            "",                  // Empty string
            String(repeating: "a", count: 254), // Too long
            "a." + String(repeating: "b", count: 64) + ".com" // Label too long
        ]
        
        for hostname in invalidHostnames {
            let result = preferencesController.isValidHostname(hostname)
            XCTAssertFalse(result, "Should validate \(hostname) as invalid hostname")
        }
    }
}

// MARK: - Port Validation Tests

extension PreferencesWindowControllerTests {
    
    func testValidPorts() {
        let validPorts = [
            "1", "80", "443", "8080", "8697", "22", "21", "25", "53", "65535"
        ]
        
        for port in validPorts {
            let result = preferencesController.validatePort(port)
            XCTAssertTrue(result, "Should validate \(port) as valid port")
        }
    }
    
    func testInvalidPorts() {
        let invalidPorts = [
            "0",        // Port 0 not allowed
            "65536",    // Port > 65535
            "-1",       // Negative port
            "abc",      // Non-numeric
            "abc123",   // Non-numeric
            "",         // Empty string
            "80.5",     // Decimal
//            "80 ",      // Trailing space (should be trimmed and valid)
            "999999"    // Way too large
        ]
        
        for port in invalidPorts {
            let result = preferencesController.validatePort(port)
            XCTAssertFalse(result, "Should validate \(port) as invalid port")
        }
    }
    
    func testPortWithWhitespace() {
        // Test that whitespace is properly trimmed
        let result = preferencesController.validatePort("  8080  ")
        XCTAssertTrue(result, "Should validate port with whitespace as valid after trimming")
    }
}

// MARK: - Username/Password Validation Tests

extension PreferencesWindowControllerTests {
    
    func testValidUsernames() {
        let validUsernames = [
            "admin", "user123", "test@example.com", "user_name", "a",
            String(repeating: "a", count: 255) // Maximum length
        ]
        
        for username in validUsernames {
            let result = preferencesController.validateUsername(username)
            XCTAssertTrue(result, "Should validate '\(username)' as valid username")
        }
    }
    
    func testInvalidUsernames() {
        let invalidUsernames = [
            "",                                    // Empty
            "   ",                                 // Only whitespace
            String(repeating: "a", count: 256)    // Too long
        ]
        
        for username in invalidUsernames {
            let result = preferencesController.validateUsername(username)
            XCTAssertFalse(result, "Should validate '\(username)' as invalid username")
        }
    }
    
    func testPasswordValidation() {
        // Valid passwords
        XCTAssertTrue(preferencesController.validatePassword("password123"))
        XCTAssertTrue(preferencesController.validatePassword(String(repeating: "a", count: 255)))
        
        // Invalid password
        XCTAssertFalse(preferencesController.validatePassword(String(repeating: "a", count: 256)))
    }
}

// MARK: - Host Validation Integration Tests

extension PreferencesWindowControllerTests {
    
    func testHostValidationIntegration() {
        // Valid hosts (IP + hostname)
        let validHosts = [
            "127.0.0.1", "example.com", "localhost", "192.168.1.1"
        ]
        
        for host in validHosts {
            let result = preferencesController.validateHost(host)
            XCTAssertTrue(result, "Should validate \(host) as valid host")
        }
        
        // Invalid hosts
        let invalidHosts = [
            "127.0.0.300",  // Invalid IP, invalid hostname (numeric components)
            "",             // Empty
            "   "           // Whitespace only
        ]
        
        for host in invalidHosts {
            let result = preferencesController.validateHost(host)
            XCTAssertFalse(result, "Should validate \(host) as invalid host")
        }
    }
}

// MARK: - UserDefaults Integration Tests

extension PreferencesWindowControllerTests {
    
    func testLoadSavedValues() {
        // Set some values in defaults
        mockDefaults.set("test.example.com", forKey: "vmrestHost")
        mockDefaults.set("9999", forKey: "vmrestPort")
        mockDefaults.set(true, forKey: "startAtLogin")
        
        // Reload values
        preferencesController.loadSavedValues()
        
        // Verify fields are populated
        XCTAssertEqual(preferencesController.hostField.stringValue, "test.example.com")
        XCTAssertEqual(preferencesController.portField.stringValue, "9999")
        XCTAssertEqual(preferencesController.startAtLoginCheckbox.state, .on)
    }
    
    func testLoadDefaultValues() {
        // Don't set any values - should use defaults
        preferencesController.loadSavedValues()
        
        // Verify default values
        XCTAssertEqual(preferencesController.hostField.stringValue, "127.0.0.1")
        XCTAssertEqual(preferencesController.portField.stringValue, "8697")
        XCTAssertEqual(preferencesController.startAtLoginCheckbox.state, .off)
    }
    
    func testSaveValidHost() {
        // Set a valid host and trigger save
        preferencesController.hostField.stringValue = "example.com"
        preferencesController.hostChanged(preferencesController.hostField)
        
        // Verify it was saved
        XCTAssertEqual(mockDefaults.string(forKey: "vmrestHost"), "example.com")
    }
    
    func testDontSaveInvalidHost() {
        // Set initial valid value
        mockDefaults.set("example.com", forKey: "vmrestHost")
        
        // Try to set invalid host
        preferencesController.hostField.stringValue = "127.0.0.300"
        preferencesController.hostChanged(preferencesController.hostField)
        
        // Verify invalid value wasn't saved
        XCTAssertEqual(mockDefaults.string(forKey: "vmrestHost"), "example.com")
    }
}

// MARK: - Field Appearance Tests

extension PreferencesWindowControllerTests {
    
    func testFieldAppearanceValidation() {
        // Set invalid values
        preferencesController.hostField.stringValue = "127.0.0.300"
        preferencesController.portField.stringValue = "70000"
        preferencesController.usernameField.stringValue = ""
        preferencesController.passwordField.stringValue = String(repeating: "a", count: 300)
        
        // Trigger validation
        preferencesController.validateAllFields()
        
        // Check that invalid fields have red background
        let redColor = NSColor.systemRed.withAlphaComponent(0.1)
        XCTAssertEqual(preferencesController.hostField.backgroundColor, redColor)
        XCTAssertEqual(preferencesController.portField.backgroundColor, redColor)
        XCTAssertEqual(preferencesController.usernameField.backgroundColor, redColor)
        XCTAssertEqual(preferencesController.passwordField.backgroundColor, redColor)
    }
    
    func testValidFieldAppearance() {
        // Set valid values
        preferencesController.hostField.stringValue = "example.com"
        preferencesController.portField.stringValue = "8080"
        
        preferencesController.usernameField.stringValue = "testuser"
        preferencesController.passwordField.stringValue = "testpass"
        
        // Trigger validation
        preferencesController.validateAllFields()
        
        // Check that valid fields have normal background
        let normalColor = NSColor.controlBackgroundColor
        XCTAssertEqual(preferencesController.hostField.backgroundColor, normalColor)
        XCTAssertEqual(preferencesController.portField.backgroundColor, normalColor)
        XCTAssertEqual(preferencesController.usernameField.backgroundColor, normalColor)
        XCTAssertEqual(preferencesController.passwordField.backgroundColor, normalColor)
    }
}

// MARK: - Button State Tests

extension PreferencesWindowControllerTests {
    
    func testTestConnectionButtonState() {
        preferencesController.updateTestConnectionButtonState()
        XCTAssertTrue(preferencesController.testConnectionButton.isEnabled)
        
        preferencesController.hostField.stringValue = "127.0.0.300"
        preferencesController.validateAllFields()
        preferencesController.updateTestConnectionButtonState()
        
        XCTAssertFalse(preferencesController.testConnectionButton.isEnabled)
        
        preferencesController.hostField.stringValue = "example.com"
        preferencesController.portField.stringValue = "8080"
        preferencesController.usernameField.stringValue = "testuser"
        preferencesController.usernameField.stringValue = "testpass"
        preferencesController.validateAllFields()
        preferencesController.updateTestConnectionButtonState()
        
        XCTAssertTrue(preferencesController.testConnectionButton.isEnabled)
    }
}

// MARK: - Window Closing Tests

extension PreferencesWindowControllerTests {
    
    func testWindowCloseWithValidData() {
        // Set valid data
        preferencesController.hostField.stringValue = "example.com"
        preferencesController.portField.stringValue = "8080"
        preferencesController.usernameField.stringValue = "testuser"
        preferencesController.passwordField.stringValue = "testpass"
        
        // Should allow closing
        let result = preferencesController.validateAndSaveAllFields()
        XCTAssertTrue(result)
        
        // Check values were saved
        XCTAssertEqual(mockDefaults.string(forKey: "vmrestHost"), "example.com")
        XCTAssertEqual(mockDefaults.string(forKey: "vmrestPort"), "8080")
    }
    
    func testWindowCloseWithInvalidDataShowsAlert() {
        // Set invalid data
        preferencesController.hostField.stringValue = "127.0.0.300"
        preferencesController.portField.stringValue = "70000"
        
        // This would normally show an alert, but in tests we can't easily mock NSAlert
        // We can test that the validation logic detects errors
        preferencesController.validateAllFields()
        
        let hostValid = preferencesController.isHostValid
        let portValid = preferencesController.isPortValid
        
        XCTAssertFalse(hostValid)
        XCTAssertFalse(portValid)
    }
}

// MARK: - Performance Tests

extension PreferencesWindowControllerTests {
    
    func testValidationPerformance() {
        let testHosts = Array(repeating: "example.com", count: 1000)
        
        measure {
            for host in testHosts {
                _ = preferencesController.validateHost(host)
            }
        }
    }
    
    func testIPValidationPerformance() {
        let testIPs = Array(repeating: "192.168.1.1", count: 1000)
        
        measure {
            for ip in testIPs {
                _ = preferencesController.isValidIPv4(ip)
            }
        }
    }
}

