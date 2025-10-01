//
//  BookmarkManager.swift
//  VMBar
//
//  Created by TJW on 9/30/25.
//

import Foundation
import AppKit

/// Centralized manager for creating, storing, resolving, and using security-scoped bookmarks
/// related to VMware Fusion:
/// - A bookmark to the vmcli binary (or a container directory such as VMware Fusion.app)
/// - A bookmark to the user's "Virtual Machines" folder
///
/// This type also provides a small RAII-style token (BookmarkAccessToken) that begins and ends
/// security-scoped resource access automatically, so callers don't forget to call
/// `stopAccessingSecurityScopedResource()`.
///
/// Persistence:
/// - Bookmarks are persisted in UserDefaults under stable keys.
/// - When creating a bookmark fails for the exact URL, the manager attempts to create a bookmark
///   for the parent directory as a fallback.
///
/// UI:
/// - When a bookmark is missing or cannot be resolved, helpers will prompt the user with an
///   NSOpenPanel on the main thread to select the appropriate folder.
/// - All prompting APIs are asynchronous and invoke their completion handlers on the same queue
///   the NSOpenPanel uses (main thread).
///
/// Threading:
/// - Prompting is always dispatched to the main queue.
/// - Bookmark resolution and token creation are fast, synchronous operations.
final class BookmarkManager {
    /// Shared singleton instance.
    static let shared = BookmarkManager()
    
    // Unique bookmark keys for different selections
    /// UserDefaults key for the vmcli (or container) bookmark.
    private let vmcliBookmarkKey = "SavedVMCLIBookmark"
    /// UserDefaults key for the "Virtual Machines" folder bookmark.
    private let vmFolderBookmarkKey = "SavedVMFolderBookmark"
    
    private init() {}
    
    // MARK: - Access Token
    
    /// RAII-style token that starts security-scoped access on init and stops it on deinit.
    ///
    /// Usage:
    /// ```
    /// let (url, token) = beginAccess(forKey: ...)
    /// defer { _ = token } // keep the token alive during use
    /// // Use `url` while `token` is in scope
    /// ```
    ///
    /// If starting access fails, initialization returns `nil`.
    final class BookmarkAccessToken {
        private let url: URL
        private let didStart: Bool
        
        /// Attempts to begin security-scoped access for the provided URL.
        /// - Parameter url: A file URL that was resolved from a security-scoped bookmark.
        /// - Returns: `nil` if `startAccessingSecurityScopedResource()` fails.
        init?(url: URL) {
            self.url = url
            self.didStart = url.startAccessingSecurityScopedResource()
            if !didStart {
                return nil
            }
        }
        
        deinit {
            if didStart {
                url.stopAccessingSecurityScopedResource()
            }
        }
    }
    
    // MARK: - Prompting
    
    /// Prompts the user to select either:
    /// - The vmcli binary's containing folder
    /// - Or VMware Fusion.app (the app bundle)
    ///
    /// The selected URL is immediately bookmarked and persisted. The completion handler receives
    /// the URL that was successfully bookmarked (or `nil` on cancel/failure).
    ///
    /// - Important: This method always presents an NSOpenPanel on the main thread.
    /// - Parameter completion: Called with the selected and successfully bookmarked URL, or `nil`.
    func promptUserToSelectVMCLIFolder(completion: @escaping (URL?) -> Void) {
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.title = "Select vmcli or VMware Fusion.app"
            panel.canChooseFiles = false
            panel.canChooseDirectories = true // Allow selecting the app bundle or a containing folder
            panel.canCreateDirectories = false
            panel.allowsMultipleSelection = false
            panel.treatsFilePackagesAsDirectories = true
            
            // Reasonable starting locations
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
            
            panel.begin { response in
                guard response == .OK, let pickedURL = panel.url else {
                    completion(nil)
                    return
                }
                
                // If the user picked the app bundle, use it as the bookmark root
                let urlToBookmark: URL
                if pickedURL.pathExtension == "app" {
                    urlToBookmark = pickedURL
                } else {
                    urlToBookmark = pickedURL
                }
                
                // Save bookmark with robust fallbacks
                if self.saveSecurityScopedBookmark(for: urlToBookmark, bookmarkKey: self.vmcliBookmarkKey) {
                    completion(urlToBookmark)
                } else {
                    // Fallback: try parent directory if a file was selected
                    let parent = urlToBookmark.deletingLastPathComponent()
                    if self.saveSecurityScopedBookmark(for: parent, bookmarkKey: self.vmcliBookmarkKey) {
                        completion(parent)
                    } else {
                        completion(nil)
                    }
                }
            }
        }
    }
    
    /// Prompts the user to select the VMware Fusion "Virtual Machines" folder.
    ///
    /// The panel attempts to start in a reasonable directory based on the provided `.vmx` path.
    /// The selected URL is immediately bookmarked and persisted. The completion handler receives
    /// the URL that was successfully bookmarked (or `nil` on cancel/failure).
    ///
    /// - Important: This method always presents an NSOpenPanel on the main thread.
    /// - Parameters:
    ///   - vmxPath: A path to a .vmx file used to infer a good starting directory.
    ///   - completion: Called with the selected and successfully bookmarked folder URL, or `nil`.
    func promptUserToSelectVMFolder(for vmxPath: String, completion: @escaping (URL?) -> Void) {
        DispatchQueue.main.async {
            let fileURL = URL(fileURLWithPath: vmxPath)
            let pathComponents = fileURL.pathComponents
            
            // Try to locate the Virtual Machines folder from the .vmx path
            let fallbackDir = fileURL.deletingLastPathComponent()
            let startDir: URL
            if let vmFolderIndex = pathComponents.firstIndex(where: { $0 == "Virtual Machines.localized" }) {
                let vmFolderComponents = pathComponents[0...vmFolderIndex]
                let vmFolderPath = NSString.path(withComponents: Array(vmFolderComponents))
                startDir = URL(fileURLWithPath: vmFolderPath)
            } else {
                startDir = fallbackDir
            }
            
            let panel = NSOpenPanel()
            panel.title = "Select VMWare Fusion's configured 'Virtual Machines' folder"
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = false
            panel.allowsMultipleSelection = false
            panel.treatsFilePackagesAsDirectories = true
            panel.directoryURL = startDir
            
            panel.begin { response in
                if response == .OK, let url = panel.url {
                    if self.saveSecurityScopedBookmark(for: url, bookmarkKey: self.vmFolderBookmarkKey) {
                        completion(url)
                    } else {
                        completion(nil)
                    }
                } else {
                    completion(nil)
                }
            }
        }
    }
    
    // MARK: - Save/Resolve Bookmark
    
    /// Creates and persists a security-scoped bookmark for a URL.
    ///
    /// Behavior:
    /// - Resolves symlinks/aliases before creating the bookmark.
    /// - On failure, attempts to create a bookmark for the parent directory as a fallback.
    ///
    /// - Parameters:
    ///   - url: The URL to bookmark.
    ///   - bookmarkKey: The UserDefaults key under which to store the bookmark data.
    /// - Returns: `true` if a bookmark (for the URL or its parent) was saved successfully.
    @discardableResult
    private func saveSecurityScopedBookmark(for url: URL, bookmarkKey: String) -> Bool {
        // Resolve symlinks/aliases before attempting to create the bookmark
        let resolvedURL = url.resolvingSymlinksInPath()
        
        do {
            let bookmarkData = try resolvedURL.bookmarkData(options: .withSecurityScope,
                                                            includingResourceValuesForKeys: nil,
                                                            relativeTo: nil)
            UserDefaults.standard.set(bookmarkData, forKey: bookmarkKey)
            return true
        } catch {
            // If bookmarking the file fails (common for alias/symlink targets), try the parent directory
            print("Failed to create '\(bookmarkKey)' bookmark for \(resolvedURL.path): \(error)")
            // Only attempt parent fallback if this is not already a root
            if resolvedURL.pathComponents.count > 1 {
                let parent = resolvedURL.deletingLastPathComponent()
                do {
                    let parentData = try parent.bookmarkData(options: .withSecurityScope,
                                                             includingResourceValuesForKeys: nil,
                                                             relativeTo: nil)
                    UserDefaults.standard.set(parentData, forKey: bookmarkKey)
                    print("Saved fallback bookmark for parent directory: \(parent.path)")
                    return true
                } catch {
                    print("Failed to create fallback parent bookmark for \(parent.path): \(error)")
                    return false
                }
            } else {
                return false
            }
        }
    }
    
    /// Resolves a previously saved security-scoped bookmark from UserDefaults.
    ///
    /// - Parameter forKey: The UserDefaults key containing bookmark data.
    /// - Returns: The resolved URL if successful and not stale; otherwise `nil`.
    private func resolveBookmarkedURL(forKey bookmarkKey: String) -> URL? {
        guard let bookmarkData = UserDefaults.standard.data(forKey: bookmarkKey) else {
            return nil
        }
        
        var isStale = false
        do {
            let url = try URL(resolvingBookmarkData: bookmarkData,
                              options: [.withSecurityScope],
                              relativeTo: nil,
                              bookmarkDataIsStale: &isStale)
            if isStale {
                print("Bookmark is stale for key: \(bookmarkKey).")
                return nil
            }
            return url
        } catch {
            print("Failed to resolve bookmark for key \(bookmarkKey): \(error)")
            return nil
        }
    }
    
    // MARK: - Scoped Access (Token-based)
    
    /// Resolves a bookmarked URL and begins security-scoped access, returning both the URL and
    /// a token that must be retained while accessing the resource.
    ///
    /// - Parameter bookmarkKey: The UserDefaults key for the bookmark to resolve.
    /// - Returns: A tuple of `(URL?, BookmarkAccessToken?)`. Both will be non-nil on success.
    private func beginAccess(forKey bookmarkKey: String) -> (URL?, BookmarkAccessToken?) {
        guard let url = resolveBookmarkedURL(forKey: bookmarkKey) else {
            return (nil, nil)
        }
        guard let token = BookmarkAccessToken(url: url) else {
            print("Failed to start accessing resource for key: \(bookmarkKey).")
            return (nil, nil)
        }
        return (url, token)
    }
    
    // MARK: - Public helpers returning URL + Token
    
    /// Begins access to the vmcli location (or prompts the user to select it if missing).
    ///
    /// Usage:
    /// ```
    /// BookmarkManager.shared.beginAccessVMCLI { url, token in
    ///     guard let url, let token else { return }
    ///     defer { _ = token } // keep token in scope while using `url`
    ///     // Use `url` here
    /// }
    /// ```
    ///
    /// - Parameter completion: Called with a resolved URL and active token, or `(nil, nil)` on failure.
    func beginAccessVMCLI(completion: @escaping (URL?, BookmarkAccessToken?) -> Void) {
        let (url, token) = beginAccess(forKey: vmcliBookmarkKey)
        if let url = url, let token = token {
            completion(url, token)
            return
        }
        
        // Prompt and then try again
        promptUserToSelectVMCLIFolder { [weak self] _ in
            guard let self = self else { return }
            let (url2, token2) = self.beginAccess(forKey: self.vmcliBookmarkKey)
            completion(url2, token2)
        }
    }
    
    /// Begins access to the "Virtual Machines" folder (or prompts the user to select it if missing).
    ///
    /// The `vmxPath` is only used to suggest a starting directory for the open panel if prompting
    /// is needed.
    ///
    /// - Parameters:
    ///   - vmxPath: A path to a .vmx file used to infer a good starting directory when prompting.
    ///   - completion: Called with a resolved folder URL and active token, or `(nil, nil)` on failure.
    func beginAccessVMFolder(for vmxPath: String, completion: @escaping (URL?, BookmarkAccessToken?) -> Void) {
        let (url, token) = beginAccess(forKey: vmFolderBookmarkKey)
        if let url = url, let token = token {
            completion(url, token)
            return
        }
        
        // Prompt and then try again
        promptUserToSelectVMFolder(for: vmxPath) { [weak self] _ in
            guard let self = self else { return }
            let (url2, token2) = self.beginAccess(forKey: self.vmFolderBookmarkKey)
            completion(url2, token2)
        }
    }
    
    // MARK: - vmcli path resolution under a bookmarked root
    
    /// Attempts to locate the vmcli binary beneath a bookmarked URL.
    ///
    /// The provided `bookmarkedURL` can be:
    /// - The app bundle (e.g., VMware Fusion.app)
    /// - The "Contents" directory inside the app bundle
    /// - The "Public" or "Library" directory inside "Contents"
    /// - The vmcli binary itself
    ///
    /// Search order:
    /// 1. If URL ends with `.app`, search inside `Contents/Public/vmcli` then `Contents/Library/vmcli`.
    /// 2. If URL is already a directory inside `Contents`, check `Public/vmcli` then `Library/vmcli`.
    /// 3. If URL itself is an executable named `vmcli`, return it.
    /// 4. If URL is a directory, check its immediate child `vmcli`.
    ///
    /// - Parameter bookmarkedURL: The root URL under which to search for `vmcli`.
    /// - Returns: A URL to an executable `vmcli` if found; otherwise `nil`.
    func vmcliURL(under bookmarkedURL: URL) -> URL? {
        var base = bookmarkedURL.resolvingSymlinksInPath()
        
        // If they bookmarked the app bundle, start at its Contents
        if base.pathExtension == "app" {
            base = base.appendingPathComponent("Contents", isDirectory: true)
        }
        
        // If they bookmarked Contents, check both common locations
        let publicCandidate = base.appendingPathComponent("Public/vmcli", isDirectory: false)
        let libraryCandidate = base.appendingPathComponent("Library/vmcli", isDirectory: false)
        
        let fm = FileManager.default
        if fm.isExecutableFile(atPath: publicCandidate.path) {
            return publicCandidate
        }
        if fm.isExecutableFile(atPath: libraryCandidate.path) {
            return libraryCandidate
        }
        
        // If they bookmarked a deeper directory (e.g., Public or Library) or the vmcli itself
        if fm.isExecutableFile(atPath: base.path), base.lastPathComponent == "vmcli" {
            return base
        }
        
        // Also check immediate children if base is a directory
        if (try? base.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            let direct = base.appendingPathComponent("vmcli", isDirectory: false)
            if fm.isExecutableFile(atPath: direct.path) {
                return direct
            }
        }
        
        return nil
    }
}
