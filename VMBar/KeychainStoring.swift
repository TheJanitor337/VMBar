//
//  KeychainStoring.swift
//  VMBar
//
//  Created by TJW on 9/25/25.
//

/// Abstraction for storing and retrieving a single username/password pair,
/// typically backed by the system Keychain on Apple platforms.
///
/// Goals:
/// - Hide the concrete storage mechanism (real Keychain vs. mock for tests).
/// - Provide simple, non-throwing APIs suitable for UI flows.
/// - Scope credentials by a `service` identifier so multiple endpoints can coexist.
///
/// Recommended semantics for conformers:
/// - Treat the credential as a single logical record per `service`.
/// - Overwrite any existing credentials for the same `service` when saving.
/// - Return `nil` from `getCredentials()` if no credentials exist or decoding fails.
/// - Make `deleteCredentials()` idempotent (return `true` if already absent).
///
/// Threading:
/// - Conformers should be safe to call from any queue.
/// - Avoid blocking the main thread for long operations.
///
/// Platform notes:
/// - A Keychain-backed implementation will typically use:
///   - `kSecClassGenericPassword`
///   - `kSecAttrService` (from `service`)
///   - `kSecAttrAccount` (for username)
///   - `kSecValueData` (for password, UTF-8 encoded)
///
/// Usage:
/// ```swift
/// let keychain: KeychainStoring = KeychainFactory.shared
/// _ = keychain.saveCredentials(username: "user", password: "secret")
/// let creds = keychain.getCredentials()
/// _ = keychain.deleteCredentials()
/// ```
public protocol KeychainStoring {
    /// Logical service identifier used to namespace credentials.
    ///
    /// In a Keychain-backed implementation, this maps to `kSecAttrService`. Use distinct values
    /// to separate environments or endpoints (e.g., dev vs. prod).
    var service: String { get }
    
    /// Saves a username/password pair for the current `service`.
    ///
    /// Expected behavior:
    /// - Overwrites any existing stored credentials for the same `service`.
    /// - Stores the username as the account identifier and the password as secret data.
    ///
    /// - Parameters:
    ///   - username: The account name to persist.
    ///   - password: The secret to persist (typically UTF-8 encoded in Keychain-backed implementations).
    /// - Returns: `true` on success; `false` if the save fails.
    func saveCredentials(username: String, password: String) -> Bool
    
    /// Retrieves the stored credentials for the current `service`, if any.
    ///
    /// - Returns: A `(username, password)` tuple on success, or `nil` if not found or on decode failure.
    func getCredentials() -> (username: String, password: String)?
    
    /// Deletes any stored credentials for the current `service`.
    ///
    /// - Returns: `true` if deletion succeeded or if no item existed (idempotent); otherwise `false`.
    func deleteCredentials() -> Bool
}

