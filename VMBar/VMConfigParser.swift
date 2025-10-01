//
//  VMConfigParser.swift
//  VMBar
//
//  Created by TJW on 10/1/25.
//

import Foundation

/// Utilities for parsing `vmcli` "ConfigParams query" output and extracting
/// high‑level information about virtual disks.
///
/// The parser operates on the plain‑text output produced by a `vmcli` config
/// query where each line is in the form:
/// - `'key': value`
///
/// Example input lines:
/// - `'nvme0.pciSlotNumber': 224`
/// - `'nvme0.present': TRUE`
/// - `'nvme0:0.fileName': 'Virtual Disk.vmdk'`
/// - `'nvme0:0.mode': independent-nonpersistent`
/// - `'nvme0:0.present': TRUE`
/// - `'nvme0:0.redo': ''`
///
/// Notes:
/// - Keys are expected to be single‑quoted. Lines not matching this pattern are ignored.
/// - Values may be unquoted, single‑quoted, numeric, or boolean. All values are returned as `String`.
/// - Surrounding single quotes around values are stripped if present; no further unescaping is performed.
/// - If duplicate keys appear, the last one encountered wins.
/// - All functions are pure and thread‑safe.
enum VMConfigParser {

    /// Parses `vmcli` "ConfigParams query" text into a `[String: String]` dictionary.
    ///
    /// Parameters:
    /// - output: The raw multi‑line string produced by `vmcli` where each line is of the form `'key': value`.
    ///
    /// Returns:
    /// A dictionary mapping the raw keys (without surrounding quotes) to their string values.
    ///
    /// Behavior:
    /// - Ignores empty lines and lines that do not start with a single quote `'`.
    /// - Extracts the key between the first pair of single quotes.
    /// - Takes the substring after the first colon `:` as the value.
    /// - Trims surrounding whitespace on the value, and strips surrounding single quotes if both the first and last character are `'`.
    /// - Does not attempt to coerce types; booleans and numbers remain strings.
    ///
    /// Complexity:
    /// - O(n) over the number of characters in `output`.
    static func parse(_ output: String) -> [String: String] {
        var map: [String: String] = [:]
        
        output.enumerateLines { rawLine, _ in
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { return }
            
            // Expect lines like: 'key': value
            guard line.first == "'" else { return }
            // Find the closing single quote after the opening one
            let afterFirst = line.index(after: line.startIndex)
            guard let keyEndIndex = line[afterFirst...].firstIndex(of: "'") else { return }
            let keyRange = afterFirst..<keyEndIndex
            let key = String(line[keyRange])
            
            // Find the colon following the key
            guard let colonIndex = line[keyEndIndex...].firstIndex(of: ":") else { return }
            let valueStart = line.index(after: colonIndex)
            var value = String(line[valueStart...]).trimmingCharacters(in: .whitespaces)
            
            // Strip surrounding single quotes if present
            if value.hasPrefix("'"), value.hasSuffix("'"), value.count >= 2 {
                value.removeFirst()
                value.removeLast()
            }
            
            map[key] = value
        }
        
        return map
    }
    
    /// A single virtual disk entry reconstructed from the generic config map.
    ///
    /// Properties:
    /// - key: The base device key in `controller:unit` form (e.g., `nvme0:0`, `scsi0:1`, `sata0:1`).
    /// - fileName: The `.vmdk` file name as reported by the config (may be relative or absolute).
    /// - rawMode: The raw VMware mode string if present (e.g., `independent-nonpersistent`, `persistent`).
    struct DiskRecord: Equatable {
        let key: String      // e.g. "nvme0:0"
        let fileName: String // e.g. "Virtual Disk.vmdk"
        let rawMode: String? // e.g. "independent-nonpersistent"
    }
    
    /// Extracts disk records from a parsed config dictionary.
    ///
    /// Parameters:
    /// - config: A dictionary produced by `parse(_:)` or an equivalent map of config keys to values.
    ///
    /// Returns:
    /// An array of `DiskRecord` items for each `.vmdk` file found, sorted by `key` using
    /// `localizedStandardCompare` (so `nvme0:9` sorts before `nvme0:10`).
    ///
    /// Detection rules:
    /// - Looks for keys ending with `.fileName`.
    /// - Requires the corresponding value to end with `.vmdk`.
    /// - Derives the base device key by removing the `.fileName` suffix.
    /// - Requires the base key to contain a colon `:` separating controller and unit.
    /// - If `<base>.mode` exists, includes it as `rawMode`; otherwise `rawMode` is `nil`.
    static func disks(from config: [String: String]) -> [DiskRecord] {
        var disks: [DiskRecord] = []
        
        for (key, value) in config {
            guard key.hasSuffix(".fileName") else { continue }
            guard value.hasSuffix(".vmdk") else { continue }
            let baseKey = String(key.dropLast(".fileName".count))
            // Expect a controller:unit format (e.g., nvme0:0, scsi0:0, sata0:1, ide0:0)
            guard baseKey.contains(":") else { continue }
            
            let modeKey = "\(baseKey).mode"
            let rawMode = config[modeKey]
            
            let record = DiskRecord(key: baseKey, fileName: value, rawMode: rawMode)
            disks.append(record)
        }
        
        return disks.sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
    }
    
    /// Normalizes VMware disk mode strings into a small, UI‑friendly set.
    ///
    /// Parameters:
    /// - raw: The raw mode string as reported by the config (e.g., `independent-nonpersistent`, `persistent`).
    ///
    /// Returns:
    /// - `"nonpersistent"` if `raw` contains the substring `nonpersistent` (case‑insensitive).
    /// - `"persistent"` if `raw` contains the substring `persistent` (case‑insensitive).
    /// - `"unknown"` if `raw` is `nil` or does not match the above.
    ///
    /// Notes:
    /// - Hyphens or underscores in `raw` are tolerated because matching is substring‑based.
    /// - Modes like `independent-persistent` normalize to `"persistent"`.
    /// - This function is intentionally conservative; it does not attempt to classify modes outside the two main categories.
    static func normalizedMode(from raw: String?) -> String {
        guard let raw = raw?.lowercased() else { return "unknown" }
        if raw.contains("nonpersistent") { return "nonpersistent" }
        if raw.contains("persistent") { return "persistent" }
        return "unknown"
    }
}

