//
//  KeychainHelper.swift
//  VMBar
//
//  Created by TJW on 9/21/25.
//

import Foundation
import Security

/// Thin wrapper around Keychain Services for storing a single username/password pair
/// associated with a service, conforming to `KeychainStoring`.
///
/// Characteristics:
/// - Uses the Generic Password class (`kSecClassGenericPassword`).
/// - Stores the username in `kSecAttrAccount` and the password as `kSecValueData` (UTF-8).
/// - Namespaces credentials by `kSecAttrService` so multiple services can coexist if needed.
/// - Overwrites any existing item for the same service when saving.
/// - Returns simple Bool/optional results to keep call sites straightforward.
///
/// Threading:
/// - Keychain Services APIs used here are safe to call from any queue.
/// - This type is stateless (aside from the `service` string), so it is safe to share.
///
/// Platform notes:
/// - On macOS, this interacts with the current user's default keychain.
/// - No access group, synchronizable, or accessibility class is specified; the system defaults apply.
///   If you need Keychain Sharing or custom accessibility (e.g., after-first-unlock), extend the queries accordingly.
struct KeychainHelper: KeychainStoring {
    /// Service name used to namespace the stored credential in the Keychain (`kSecAttrService`).
    ///
    /// You can change this to isolate credentials per environment or endpoint if your app supports
    /// multiple backends (e.g., "com.example.app.vmrest.dev" vs "com.example.app.vmrest.prod").
    var service = "com.ixqus.VMBar.vmrest"

    /// Saves both username and password together as a single Generic Password item.
    ///
    /// Behavior:
    /// - Deletes any existing item for this `service` to avoid duplicates.
    /// - Adds a new item with:
    ///   - `kSecAttrService` = `service`
    ///   - `kSecAttrAccount` = `username`
    ///   - `kSecValueData` = `password` encoded as UTF-8
    ///
    /// - Parameters:
    ///   - username: The account name to store in `kSecAttrAccount`.
    ///   - password: The secret to store in `kSecValueData` (UTF-8 encoded).
    /// - Returns: `true` if the item was added successfully; otherwise `false`.
    ///
    /// Notes:
    /// - This method overwrites any previously saved item for the same service.
    /// - No Keychain sharing group or custom accessibility class is specified.
    func saveCredentials(username: String, password: String) -> Bool {
        guard let passwordData = password.data(using: .utf8) else { return false }

        // Delete any existing item for this service
        let deleteQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new item
        let addQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: username,
            kSecValueData: passwordData
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Loads the stored username and password (if present) for the current `service`.
    ///
    /// Behavior:
    /// - Queries the Keychain for a single Generic Password item matching `kSecAttrService = service`.
    /// - Requests both attributes and data (`kSecReturnAttributes`, `kSecReturnData`).
    ///
    /// - Returns: A tuple `(username: String, password: String)` on success, or `nil` if:
    ///   - No matching item exists,
    ///   - The item cannot be decoded, or
    ///   - The Keychain query fails.
    func getCredentials() -> (username: String, password: String)? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecReturnAttributes: true,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let existing = item as? [String: Any],
              let account = existing[kSecAttrAccount as String] as? String,
              let pwData = existing[kSecValueData as String] as? Data,
              let password = String(data: pwData, encoding: .utf8)
        else {
            return nil
        }
        return (username: account, password: password)
    }

    /// Deletes any stored credentials for the current `service`.
    ///
    /// - Returns: `true` if the delete succeeded or if no item was found (idempotent behavior),
    ///   otherwise `false`.
    ///
    /// Notes:
    /// - This removes all Generic Password items that match `kSecAttrService = service`.
    func deleteCredentials() -> Bool {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

