//
//  KeychainFactory.swift
//  VMBar
//
//  Created by TJW on 9/25/25.
//

import Foundation

/// Factory for providing a process-wide Keychain storage implementation.
///
/// Behavior:
/// - Returns a real Keychain-backed implementation in normal app runs.
/// - Returns a mock in test contexts to avoid touching the system Keychain.
///
/// How testing is detected:
/// - If the process is launched with the command-line argument `--testing`.
/// - Or if the environment variable `VMBarTesting` is set to `"1"`.
///
/// Usage:
/// ```swift
/// let keychain: KeychainStoring = KeychainFactory.shared
/// // Use `keychain` without worrying whether it's the real or mock implementation.
/// ```
enum KeychainFactory {
    /// Lazily initialized, process-wide keychain storage instance.
    ///
    /// Resolution rules:
    /// - If `--testing` appears in `CommandLine.arguments`, a `MockKeychainHelper` is returned.
    /// - If the environment variable `VMBarTesting` equals `"1"`, a `MockKeychainHelper` is returned.
    /// - Otherwise, a production `KeychainHelper` is returned.
    ///
    /// Notes:
    /// - Initialization occurs on first access.
    /// - The returned type conforms to `KeychainStoring`, allowing call sites to remain agnostic.
    static var shared: KeychainStoring = {
        let isTestingArg = CommandLine.arguments.contains("--testing")
        
        var isTestingEnv = false
        if let cString = getenv("VMBarTesting"),
           let value = String(validatingUTF8: cString) {
            isTestingEnv = value == "1"
        }
        
        if isTestingArg || isTestingEnv {
            return MockKeychainHelper()
        } else {
            return KeychainHelper()
        }
    }()
}
