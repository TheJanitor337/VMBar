//
//  VMCLIHelper.swift
//  VMBar
//
//  Created by TJW on 9/30/25.
//

import Foundation
import AppKit

/// A small utility for invoking VMware Fusion's command‑line tool (vmcli).
///
/// VMCLIHelper provides two primary entry points:
/// - `runVMCLIConfigParamsQuery(withVMXPath:vmcliURL:completion:)` which executes vmcli and returns the raw combined stdout/stderr as a String.
/// - `runVMCLIConfigParamsQueryParsed(withVMXPath:vmcliURL:completion:)` which parses that output into a `[String: String]` using `VMConfigParser`.
///
/// Notes:
/// - All work is performed off the main thread on a background queue. The completion handlers are invoked on that same background queue; callers that update UI should hop back to the main actor/thread.
/// - Both stdout and stderr are captured and combined; errors from vmcli are surfaced via a non‑zero exit status and the captured output.
/// - The helper validates that the vmcli binary exists and is executable before attempting to run it.
class VMCLIHelper {
    /// Default filesystem path to VMware Fusion's `vmcli` binary.
    ///
    /// Change this if your installation is in a non‑standard location, or pass a custom URL to the methods below.
    static let defaultVMCLIPath = "/Applications/VMware Fusion.app/Contents/Public/vmcli"
    
    /// Executes `vmcli` to run `ConfigParams query` against a given `.vmx` path and returns the raw combined output.
    ///
    /// This method:
    /// - Validates that the vmcli binary exists and is executable (using `vmcliURL` if provided, otherwise `defaultVMCLIPath`).
    /// - Launches a `Process` with arguments `[vmxPath, "ConfigParams", "query"]`.
    /// - Captures both stdout and stderr into a single String (UTF‑8).
    /// - Calls `completion` with `.success(output)` if the process exits with status 0, otherwise `.failure(.nonZeroExit(status, output))`.
    ///
    /// Threading:
    /// - Work is dispatched to a `.userInitiated` global queue.
    /// - Completion is invoked on that background queue; no main‑thread guarantee is provided.
    ///
    /// - Parameters:
    ///   - vmxPath: Absolute path to the `.vmx` file for the virtual machine.
    ///   - vmcliURL: Optional explicit URL to the `vmcli` binary. If `nil`, `defaultVMCLIPath` is used.
    ///   - completion: Closure invoked with a `Result` containing the raw String output on success or an `Error` on failure.
    ///
    /// Errors:
    /// - `.vmcliNotFound` if the binary cannot be found or is not executable.
    /// - `.outputDecodingFailed` if the process output cannot be decoded as UTF‑8.
    /// - `.nonZeroExit(code, output)` if `vmcli` exits with a non‑zero status.
    ///
    /// Example:
    /// ```
    /// VMCLIHelper.runVMCLIConfigParamsQuery(withVMXPath: "/path/to/vm.vmx") { result in
    ///     switch result {
    ///     case .success(let output):
    ///         print(output)
    ///     case .failure(let error):
    ///         print("Failed: \(error)")
    ///     }
    /// }
    /// ```
    static func runVMCLIConfigParamsQuery(withVMXPath vmxPath: String,
                                          vmcliURL: URL? = nil,
                                          completion: @escaping (Result<String, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let executableURL = vmcliURL ?? URL(fileURLWithPath: defaultVMCLIPath)
            
            guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
                completion(.failure(VMCLIError.vmcliNotFound))
                return
            }
            
            let process = Process()
            process.executableURL = executableURL
            process.arguments = [vmxPath, "ConfigParams", "query"]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
                process.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                guard let output = String(data: data, encoding: .utf8) else {
                    completion(.failure(VMCLIError.outputDecodingFailed))
                    return
                }

                if process.terminationStatus == 0 {
                    completion(.success(output))
                } else {
                    completion(.failure(VMCLIError.nonZeroExit(process.terminationStatus, output)))
                }
            } catch {
                completion(.failure(error))
            }
        }
    }
    
    /// Executes `ConfigParams query` and returns a parsed key/value dictionary.
    ///
    /// This is a convenience wrapper around `runVMCLIConfigParamsQuery(withVMXPath:vmcliURL:completion:)`
    /// that parses the raw output using `VMConfigParser.parse(_:)`.
    ///
    /// Threading:
    /// - Work and completion occur on a background queue; callers should dispatch to the main actor if updating UI.
    ///
    /// - Parameters:
    ///   - vmxPath: Absolute path to the `.vmx` file for the virtual machine.
    ///   - vmcliURL: Optional explicit URL to the `vmcli` binary. If `nil`, `defaultVMCLIPath` is used.
    ///   - completion: Closure invoked with a `Result` containing a `[String: String]` on success or an `Error` on failure.
    ///
    /// See also:
    /// - `VMConfigParser.parse(_:)` for the parsing rules applied to the vmcli output.
    static func runVMCLIConfigParamsQueryParsed(withVMXPath vmxPath: String,
                                                vmcliURL: URL? = nil,
                                                completion: @escaping (Result<[String: String], Error>) -> Void) {
        runVMCLIConfigParamsQuery(withVMXPath: vmxPath, vmcliURL: vmcliURL) { result in
            switch result {
            case .success(let output):
                let map = VMConfigParser.parse(output)
                completion(.success(map))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Errors that can occur while invoking and processing `vmcli`.
    enum VMCLIError: Error, LocalizedError {
        /// The `vmcli` binary could not be found at the expected path or is not executable.
        case vmcliNotFound
        /// The process output could not be decoded as UTF‑8 text.
        case outputDecodingFailed
        /// `vmcli` exited with a non‑zero code. Associated values are `(exitCode, combinedOutput)`.
        case nonZeroExit(Int32, String)

        /// A human‑readable description suitable for displaying to users.
        var errorDescription: String? {
            switch self {
            case .vmcliNotFound:
                return "vmcli binary not found or not executable at expected path."
            case .outputDecodingFailed:
                return "Failed to decode vmcli output."
            case .nonZeroExit(let code, let output):
                return "vmcli exited with code \(code): \(output)"
            }
        }
    }
}
