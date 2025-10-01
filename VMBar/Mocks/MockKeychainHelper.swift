//
//  MockKeychainHelper.swift
//  VMBar
//
//  Created by TJW on 9/25/25.
//

#if DEBUG
import Foundation
import Security

class MockKeychainHelper: KeychainStoring {
    var service = "com.ixqus.VMBar.testvmrest"
    
    private var storage: [String: String] = [:]

    func saveCredentials(username: String, password: String) -> Bool {
        storage["username"] = username
        storage["password"] = password
        return true
    }

    func getCredentials() -> (username: String, password: String)? {
        let credentials = fetchCredentials()
        storage["username"] = credentials?.username
        storage["password"] = credentials?.password
        return (username: credentials?.username, password: credentials?.password) as? (username: String, password: String)
    }

    func deleteCredentials() -> Bool {
        storage.removeAll()
        return true
    }
    
    func fetchCredentials() -> (username: String, password: String)? {
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
}
#endif
