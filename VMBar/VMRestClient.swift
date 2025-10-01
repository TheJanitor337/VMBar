//
//  VMRestClient.swift
//  VMBar
//
//  Created by TJW on 9/23/25.
//

import Foundation

// MARK: - Error Types

/// Errors that can occur when communicating with the VMware vmrest service.
enum VMRestError: Error, LocalizedError {
    /// The constructed URL is invalid.
    case invalidURL
    /// A transport-level networking error occurred.
    case networkError(Error)
    /// The server returned an HTTP error status with an optional message.
    case httpError(statusCode: Int, message: String?)
    /// Decoding of the response payload failed.
    case decodingError(Error)
    /// Authentication failed (typically HTTP 401).
    case authenticationFailed
    /// The caller lacks permission to perform the operation (typically HTTP 403).
    case permissionDenied
    /// The requested resource could not be found (typically HTTP 404).
    case notFound
    /// The request conflicts with current resource state (typically HTTP 409).
    case conflict
    /// An unspecified server-side error occurred.
    case serverError
    
    /// Human-readable description of the error suitable for UI presentation or logging.
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .httpError(let statusCode, let message):
            return "HTTP \(statusCode): \(message ?? "Unknown error")"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .authenticationFailed:
            return "Authentication failed"
        case .permissionDenied:
            return "Permission denied"
        case .notFound:
            return "Resource not found"
        case .conflict:
            return "Resource state conflicts"
        case .serverError:
            return "Server error"
        }
    }
}

// MARK: - Response Models

/// Canonical error response payload returned by vmrest endpoints.
struct VMRestErrorResponse: Codable {
    /// Numeric error code provided by the service.
    let code: Int
    /// Human-readable error message.
    let message: String
}

// MARK: - VMRestClient

/// A lightweight client for the VMware vmrest API used by VMware Fusion/Workstation.
///
/// This client encapsulates URLSession configuration (including Basic authentication),
/// request construction, common error handling, and JSON encoding/decoding for a subset
/// of vmrest endpoints.
///
/// Unless otherwise noted, all methods are asynchronous and deliver results via completion
/// handlers that contain a Swift `Result` with either the decoded model or a `VMRestError`.
class VMRestClient {
    /// Base URL of the vmrest service, e.g. "http://127.0.0.1:8697".
    private var baseURL: String
    /// URLSession used for all network requests.
    private let session: URLSession
    /// Content type used for requests and responses to/from vmrest.
    private let contentType: String = "application/vnd.vmware.vmw.rest-v1+json"
    
    // Debug proxy settings
    
    /// Whether to route traffic through a local debugging proxy (e.g., Proxyman/Charles/Fiddler).
    private let useDebugProxy: Bool = false
    /// Hostname/IP of the debugging proxy.
    private let debugProxyHost: String = "127.0.0.1"
    /// Port of the debugging proxy.
    private let debugProxyPort: Int = 8888
    
    // MARK: - Initialization
    
    /// Creates a new client configured for a specific base URL and Basic authentication.
    ///
    /// - Parameters:
    ///   - baseURL: The base URL of the vmrest service, such as "http://127.0.0.1:8697".
    ///   - username: Username for Basic authentication.
    ///   - password: Password for Basic authentication.
    ///
    /// The initializer configures a URLSession that automatically includes Authorization,
    /// Content-Type, and Accept headers for all requests. If `useDebugProxy` is enabled,
    /// requests are routed through the configured debugging proxy.
    init(baseURL: String, username: String, password: String) {
        self.baseURL = baseURL
        
        let config = URLSessionConfiguration.default
        let userPasswordString = "\(username):\(password)"
        let tokenData = userPasswordString.data(using: .utf8)!
        let authToken = "Basic \(tokenData.base64EncodedString())"
        config.httpAdditionalHeaders = [
            "Authorization": authToken,
            "Content-Type": contentType,
            "Accept": contentType
        ]
        
        if useDebugProxy {
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            config.connectionProxyDictionary = [
                kCFNetworkProxiesHTTPEnable as String: 1,
                kCFNetworkProxiesHTTPProxy as String: debugProxyHost,
                kCFNetworkProxiesHTTPPort as String: debugProxyPort
            ]
        }
        
        self.session = URLSession(configuration: config)
    }
    
    /// Convenience initializer that builds the base URL from UserDefaults.
    ///
    /// - Parameters:
    ///   - username: Username for Basic authentication.
    ///   - password: Password for Basic authentication.
    ///
    /// - Discussion:
    /// Reads `vmrestHost` and `vmrestPort` from `UserDefaults.standard` to construct the base URL.
    /// Defaults to host "127.0.0.1" and port "8697" if the keys are not present.
    convenience init(username: String, password: String) {
        let defaults = UserDefaults.standard
        let host = defaults.string(forKey: "vmrestHost") ?? "127.0.0.1"
        let port = defaults.string(forKey: "vmrestPort") ?? "8697"
        let baseURL = "http://\(host):\(port)"
        
        self.init(baseURL: baseURL, username: username, password: password)
    }
    
    // MARK: - Generic Request Handler
    
    /// Performs a request to the vmrest API and decodes the response into the given type.
    ///
    /// - Parameters:
    ///   - endpoint: The path component to append to the base URL (e.g., "/api/vms").
    ///   - method: HTTP method to use. Defaults to "GET".
    ///   - body: Optional HTTP body data. If present, the Content-Type header is set.
    ///   - completion: Completion handler with a `Result` containing the decoded model of type `T`
    ///                 or a `VMRestError` describing the failure.
    ///
    /// - Discussion:
    ///   This method handles common HTTP status codes, decoding success payloads with `JSONDecoder`,
    ///   and mapping error responses to `VMRestError`. For endpoints that are expected to return no
    ///   content, pass `T == EmptyResponse` to receive an empty success result when the body is empty
    ///   or the status code is 204.
    private func request<T: Decodable>(
        endpoint: String,
        method: String = "GET",
        body: Data? = nil,
        completion: @escaping (Result<T, VMRestError>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            completion(.failure(.invalidURL))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        
        if body != nil {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        
        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(.networkError(error)))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(.serverError))
                return
            }
            
            // Handle HTTP status codes
            switch httpResponse.statusCode {
            case 200, 201:
                // Success with an empty body.
                if self.isEmptyBody(data) {
//                    TODO: Use swagger.json to update requests with EmptyResponse for responses that are expected to be empty.
                    if T.self == EmptyResponse.self {
                        completion(.success(EmptyResponse() as! T))
                    } else {
                        completion(.failure(.serverError))
                    }
                    return
                }
                
                guard let data = data else {
                    completion(.failure(.serverError))
                    return
                }
                
                do {
                    let decoded = try JSONDecoder().decode(T.self, from: data)
                    completion(.success(decoded))
                } catch {
                    completion(.failure(.decodingError(error)))
                }
                
            case 204:
                // No content - create empty response if T is Void-like
                if self.isEmptyBody(data) {
                    if T.self == EmptyResponse.self {
                        completion(.success(EmptyResponse() as! T))
                    } else {
                        completion(.failure(.serverError))
                    }
                    return
                }
                
            case 400:
                let message = self.parseErrorMessage(from: data)
                completion(.failure(.httpError(statusCode: 400, message: message)))
                
            case 401:
                completion(.failure(.authenticationFailed))
                
            case 403:
                completion(.failure(.permissionDenied))
                
            case 404:
                completion(.failure(.notFound))
                
            case 406:
                completion(.failure(.httpError(statusCode: 406, message: "Content type not supported")))
                
            case 409:
                completion(.failure(.conflict))
                
            case 500...599:
                let message = self.parseErrorMessage(from: data)
                completion(.failure(.httpError(statusCode: httpResponse.statusCode, message: message)))
                
            default:
                let message = self.parseErrorMessage(from: data)
                completion(.failure(.httpError(statusCode: httpResponse.statusCode, message: message)))
            }
        }
        
        task.resume()
    }
    
    /// Attempts to parse a vmrest error message from a response body.
    ///
    /// - Parameter data: The response body data, if any.
    /// - Returns: A human-readable message parsed from a `VMRestErrorResponse`, or a UTF-8 string fallback,
    ///            or `nil` if no data is available.
    private func parseErrorMessage(from data: Data?) -> String? {
        guard let data = data else { return nil }
        
        do {
            let errorResponse = try JSONDecoder().decode(VMRestErrorResponse.self, from: data)
            return errorResponse.message
        } catch {
            return String(data: data, encoding: .utf8)
        }
    }
    
    /// Determines whether the given response body is effectively empty.
    ///
    /// - Parameter data: The response body data, if any.
    /// - Returns: `true` if `data` is `nil`, empty, whitespace-only, or equals the literal "null"; otherwise `false`.
    private func isEmptyBody(_ data: Data?) -> Bool {
        guard let data = data else { return true }
        if data.isEmpty { return true }
        if let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           text.isEmpty || text == "null" {
            return true
        }
        return false
    }
    
    // MARK: - VM Management
    
    /// Retrieves the list of registered VMs, including IDs and paths.
    ///
    /// - Parameter completion: Completion with an array of `VMModel` on success or `VMRestError` on failure.
    func fetchVMs(completion: @escaping (Result<[VMModel], VMRestError>) -> Void) {
        request(endpoint: "/api/vms", completion: completion)
    }
    
    /// Retrieves detailed configuration information for a specific VM.
    ///
    /// - Parameters:
    ///   - id: The VM identifier.
    ///   - completion: Completion with `VMInformation` on success or `VMRestError` on failure.
    func getVM(id: String, completion: @escaping (Result<VMInformation, VMRestError>) -> Void) {
        request(endpoint: "/api/vms/\(id)", completion: completion)
    }
    
    /// Updates the configuration of a specific VM.
    ///
    /// - Parameters:
    ///   - id: The VM identifier.
    ///   - parameters: The new configuration values to apply.
    ///   - completion: Completion with updated `VMInformation` on success or `VMRestError` on failure.
    func updateVM(id: String, parameters: VMParameter, completion: @escaping (Result<VMInformation, VMRestError>) -> Void) {
        guard let body = try? JSONEncoder().encode(parameters) else {
            completion(.failure(.serverError))
            return
        }
        request(endpoint: "/api/vms/\(id)", method: "PUT", body: body, completion: completion)
    }
    
    /// Deletes a VM from the library.
    ///
    /// - Parameters:
    ///   - id: The VM identifier.
    ///   - completion: Completion with `EmptyResponse` on success or `VMRestError` on failure.
    func deleteVM(id: String, completion: @escaping (Result<EmptyResponse, VMRestError>) -> Void) {
        request(endpoint: "/api/vms/\(id)", method: "DELETE", completion: completion)
    }
    
    /// Creates a clone of an existing VM.
    ///
    /// - Parameters:
    ///   - parameters: Clone options describing the source and target.
    ///   - completion: Completion with `VMInformation` for the new VM on success or `VMRestError` on failure.
    func cloneVM(parameters: VMCloneParameter, completion: @escaping (Result<VMInformation, VMRestError>) -> Void) {
        guard let body = try? JSONEncoder().encode(parameters) else {
            completion(.failure(.serverError))
            return
        }
        request(endpoint: "/api/vms", method: "POST", body: body, completion: completion)
    }
    
    /// Registers an existing VMX file with the VM library.
    ///
    /// - Parameters:
    ///   - name: Display name to assign to the VM in the library.
    ///   - path: Absolute filesystem path to the VMX file.
    ///   - completion: Completion with `VMRegistrationInformation` on success or `VMRestError` on failure.
    func registerVM(name: String, path: String, completion: @escaping (Result<VMRegistrationInformation, VMRestError>) -> Void) {
        let parameters = VMRegisterParameter(name: name, path: path)
        guard let body = try? JSONEncoder().encode(parameters) else {
            completion(.failure(.serverError))
            return
        }
        request(endpoint: "/api/vms/registration", method: "POST", body: body, completion: completion)
    }
    
    /// Retrieves the restrictions (e.g., policy/locking) applied to a VM.
    ///
    /// - Parameters:
    ///   - id: The VM identifier.
    ///   - completion: Completion with `VMRestrictionsInformation` on success or `VMRestError` on failure.
    func getVMRestrictions(id: String, completion: @escaping (Result<VMRestrictionsInformation, VMRestError>) -> Void) {
        request(endpoint: "/api/vms/\(id)/restrictions", completion: completion)
    }
    
    // MARK: - VM Parameters
    
    /// Retrieves a specific VM configuration parameter by name.
    ///
    /// - Parameters:
    ///   - vmId: The VM identifier.
    ///   - paramName: The configuration parameter key.
    ///   - completion: Completion with `VMParameter` on success or `VMRestError` on failure.
    func fetchVMParam(vmId: String, paramName: String, completion: @escaping (Result<VMParameter, VMRestError>) -> Void) {
        request(endpoint: "/api/vms/\(vmId)/params/\(paramName)", completion: completion)
    }
    
    /// Updates one or more VM configuration parameters.
    ///
    /// - Parameters:
    ///   - vmId: The VM identifier.
    ///   - parameters: The parameters to update.
    ///   - completion: Completion with `EmptyResponse` on success or `VMRestError` on failure.
    func updateVMParams(vmId: String, parameters: VMParameter, completion: @escaping (Result<EmptyResponse, VMRestError>) -> Void) {
        guard let body = try? JSONEncoder().encode(parameters) else {
            completion(.failure(.serverError))
            return
        }
        request(endpoint: "/api/vms/\(vmId)/params", method: "PUT", body: body, completion: completion)
    }
    
    // MARK: - Power Management
    
    /// Retrieves the current power state of a VM.
    ///
    /// - Parameters:
    ///   - vmId: The VM identifier.
    ///   - completion: Completion with `VMPowerState` on success or `VMRestError` on failure.
    func getPowerState(vmId: String, completion: @escaping (Result<VMPowerState, VMRestError>) -> Void) {
        request(endpoint: "/api/vms/\(vmId)/power", completion: completion)
    }
    
    /// Performs a power action on a VM (e.g., on, off, shutdown, suspend, pause, unpause).
    ///
    /// - Parameters:
    ///   - vmId: The VM identifier.
    ///   - action: The power action to perform. Expected values are defined by the vmrest API.
    ///   - completion: Completion with the resulting `VMPowerState` on success or `VMRestError` on failure.
    func performPowerAction(vmId: String, action: String, completion: @escaping (Result<VMPowerState, VMRestError>) -> Void) {
        let body = action.data(using: .utf8)
        request(endpoint: "/api/vms/\(vmId)/power", method: "PUT", body: body, completion: completion)
    }
    
    // MARK: - Network Adapters Management
    
    /// Retrieves all network adapters configured on a VM.
    ///
    /// - Parameters:
    ///   - vmId: The VM identifier.
    ///   - completion: Completion with `NICDevices` on success or `VMRestError` on failure.
    func getAllNICDevices(vmId: String, completion: @escaping (Result<NICDevices, VMRestError>) -> Void) {
        request(endpoint: "/api/vms/\(vmId)/nic", completion: completion)
    }
    
    /// Creates a new network adapter on a VM.
    ///
    /// - Parameters:
    ///   - vmId: The VM identifier.
    ///   - parameters: The adapter configuration to create.
    ///   - completion: Completion with the created `NICDevice` on success or `VMRestError` on failure.
    func createNICDevice(vmId: String, parameters: NICDeviceParameter, completion: @escaping (Result<NICDevice, VMRestError>) -> Void) {
        guard let body = try? JSONEncoder().encode(parameters) else {
            completion(.failure(.serverError))
            return
        }
        request(endpoint: "/api/vms/\(vmId)/nic", method: "POST", body: body, completion: completion)
    }
    
    /// Updates an existing network adapter on a VM.
    ///
    /// - Parameters:
    ///   - vmId: The VM identifier.
    ///   - index: The adapter index as expected by the vmrest API.
    ///   - parameters: The new adapter configuration.
    ///   - completion: Completion with the updated `NICDevice` on success or `VMRestError` on failure.
    func updateNICDevice(vmId: String, index: String, parameters: NICDeviceParameter, completion: @escaping (Result<NICDevice, VMRestError>) -> Void) {
        guard let body = try? JSONEncoder().encode(parameters) else {
            completion(.failure(.serverError))
            return
        }
        request(endpoint: "/api/vms/\(vmId)/nic/\(index)", method: "PUT", body: body, completion: completion)
    }
    
    /// Deletes a network adapter from a VM.
    ///
    /// - Parameters:
    ///   - vmId: The VM identifier.
    ///   - index: The adapter index to delete.
    ///   - completion: Completion with `EmptyResponse` on success or `VMRestError` on failure.
    func deleteNICDevice(vmId: String, index: String, completion: @escaping (Result<EmptyResponse, VMRestError>) -> Void) {
        request(endpoint: "/api/vms/\(vmId)/nic/\(index)", method: "DELETE", completion: completion)
    }
    
    /// Retrieves the primary IP address of a VM (as known to vmrest).
    ///
    /// - Parameters:
    ///   - vmId: The VM identifier.
    ///   - completion: Completion with `VMIPAddress` on success or `VMRestError` on failure.
    func getIPAddress(vmId: String, completion: @escaping (Result<VMIPAddress, VMRestError>) -> Void) {
        request(endpoint: "/api/vms/\(vmId)/ip", completion: completion)
    }
    
    /// Retrieves the IP stack configuration for all NICs on a VM.
    ///
    /// - Parameters:
    ///   - vmId: The VM identifier.
    ///   - completion: Completion with `NicIpStackAll` on success or `VMRestError` on failure.
    func getNICIPStack(vmId: String, completion: @escaping (Result<NicIpStackAll, VMRestError>) -> Void) {
        request(endpoint: "/api/vms/\(vmId)/nicips", completion: completion)
    }
    
    // MARK: - Shared Folders Management
    
    /// Retrieves all shared folders mounted in a VM.
    ///
    /// - Parameters:
    ///   - vmId: The VM identifier.
    ///   - completion: Completion with an array of `SharedFolder` on success or `VMRestError` on failure.
    func getAllSharedFolders(vmId: String, completion: @escaping (Result<[SharedFolder], VMRestError>) -> Void) {
        request(endpoint: "/api/vms/\(vmId)/sharedfolders", completion: completion)
    }
    
    /// Mounts a new shared folder in a VM.
    ///
    /// - Parameters:
    ///   - vmId: The VM identifier.
    ///   - folder: The shared folder configuration to create.
    ///   - completion: Completion with the updated array of `SharedFolder` on success or `VMRestError` on failure.
    func createSharedFolder(vmId: String, folder: SharedFolder, completion: @escaping (Result<[SharedFolder], VMRestError>) -> Void) {
        guard let body = try? JSONEncoder().encode(folder) else {
            completion(.failure(.serverError))
            return
        }
        request(endpoint: "/api/vms/\(vmId)/sharedfolders", method: "POST", body: body, completion: completion)
    }
    
    /// Updates an existing shared folder in a VM.
    ///
    /// - Parameters:
    ///   - vmId: The VM identifier.
    ///   - folderId: The identifier of the shared folder to update.
    ///   - parameters: The new shared folder parameters.
    ///   - completion: Completion with the updated array of `SharedFolder` on success or `VMRestError` on failure.
    func updateSharedFolder(vmId: String, folderId: String, parameters: SharedFolderParameter, completion: @escaping (Result<[SharedFolder], VMRestError>) -> Void) {
        guard let body = try? JSONEncoder().encode(parameters) else {
            completion(.failure(.serverError))
            return
        }
        request(endpoint: "/api/vms/\(vmId)/sharedfolders/\(folderId)", method: "PUT", body: body, completion: completion)
    }
    
    /// Deletes a shared folder from a VM.
    ///
    /// - Parameters:
    ///   - vmId: The VM identifier.
    ///   - folderId: The identifier of the shared folder to delete.
    ///   - completion: Completion with `EmptyResponse` on success or `VMRestError` on failure.
    func deleteSharedFolder(vmId: String, folderId: String, completion: @escaping (Result<EmptyResponse, VMRestError>) -> Void) {
        request(endpoint: "/api/vms/\(vmId)/sharedfolders/\(folderId)", method: "DELETE", completion: completion)
    }
    
    // MARK: - Host Networks Management
    
    /// Retrieves all virtual networks (vmnet) on the host.
    ///
    /// - Parameter completion: Completion with `Networks` on success or `VMRestError` on failure.
    func getAllNetworks(completion: @escaping (Result<Networks, VMRestError>) -> Void) {
        request(endpoint: "/api/vmnet", completion: completion)
    }
    
    /// Creates a new virtual network (vmnet).
    ///
    /// - Parameters:
    ///   - parameters: The network creation parameters.
    ///   - completion: Completion with the created `Network` on success or `VMRestError` on failure.
    func createNetwork(parameters: CreateVmnetParameter, completion: @escaping (Result<Network, VMRestError>) -> Void) {
        guard let body = try? JSONEncoder().encode(parameters) else {
            completion(.failure(.serverError))
            return
        }
        request(endpoint: "/api/vmnets", method: "POST", body: body, completion: completion)
    }
    
    /// Retrieves all port forwarding rules for a given vmnet.
    ///
    /// - Parameters:
    ///   - vmnet: The vmnet identifier (e.g., "vmnet8").
    ///   - completion: Completion with `Portforwards` on success or `VMRestError` on failure.
    func getPortForwards(vmnet: String, completion: @escaping (Result<Portforwards, VMRestError>) -> Void) {
        request(endpoint: "/api/vmnet/\(vmnet)/portforward", completion: completion)
    }
    
    /// Updates a specific port forwarding rule.
    ///
    /// - Parameters:
    ///   - vmnet: The vmnet identifier (e.g., "vmnet8").
    ///   - protocol: The transport protocol ("tcp" or "udp").
    ///   - port: The host port for the forwarding rule.
    ///   - parameters: The new forwarding parameters.
    ///   - completion: Completion with `VMRestErrorResponse` on success or `VMRestError` on failure.
    func updatePortForward(vmnet: String, protocol: String, port: Int, parameters: PortforwardParameter, completion: @escaping (Result<VMRestErrorResponse, VMRestError>) -> Void) {
        guard let body = try? JSONEncoder().encode(parameters) else {
            completion(.failure(.serverError))
            return
        }
//        TODO: Does `protocol` work?
        request(endpoint: "/api/vmnet/\(vmnet)/portforward/\(`protocol`)/\(port)", method: "PUT", body: body, completion: completion)
    }
    
    /// Deletes a specific port forwarding rule.
    ///
    /// - Parameters:
    ///   - vmnet: The vmnet identifier (e.g., "vmnet8").
    ///   - protocol: The transport protocol ("tcp" or "udp").
    ///   - port: The host port for the forwarding rule.
    ///   - completion: Completion with `EmptyResponse` on success or `VMRestError` on failure.
    func deletePortForward(vmnet: String, protocol: String, port: Int, completion: @escaping (Result<EmptyResponse, VMRestError>) -> Void) {
        //        TODO: Does `protocol` work?
        request(endpoint: "/api/vmnet/\(vmnet)/portforward/\(`protocol`)/\(port)", method: "DELETE", completion: completion)
    }
    
    /// Retrieves all MAC-to-IP reservation bindings for the DHCP service on a vmnet.
    ///
    /// - Parameters:
    ///   - vmnet: The vmnet identifier (e.g., "vmnet8").
    ///   - completion: Completion with `MACToIPs` on success or `VMRestError` on failure.
    func getMACToIPs(vmnet: String, completion: @escaping (Result<MACToIPs, VMRestError>) -> Void) {
        request(endpoint: "/api/vmnet/\(vmnet)/mactoip", completion: completion)
    }
    
    /// Updates or creates a MAC-to-IP reservation binding for the DHCP service on a vmnet.
    ///
    /// - Parameters:
    ///   - vmnet: The vmnet identifier (e.g., "vmnet8").
    ///   - mac: The MAC address to bind.
    ///   - ip: The IP address to reserve for the MAC.
    ///   - completion: Completion with `VMRestErrorResponse` on success or `VMRestError` on failure.
    func updateMACToIP(vmnet: String, mac: String, ip: String, completion: @escaping (Result<VMRestErrorResponse, VMRestError>) -> Void) {
        let parameters = MacToIPParameter(ip: ip)
        guard let body = try? JSONEncoder().encode(parameters) else {
            completion(.failure(.serverError))
            return
        }
        request(endpoint: "/api/vmnet/\(vmnet)/mactoip/\(mac)", method: "PUT", body: body, completion: completion)
    }
    
    // MARK: - Connection Test
    
    /// Performs a simple connectivity test against the vmrest API.
    ///
    /// - Parameter completion: Completion with `true` if a simple request succeeds, `false` otherwise.
    func testConnection(completion: @escaping (Bool) -> Void) {
        fetchVMs { result in
            switch result {
            case .success:
                completion(true)
            case .failure:
                completion(false)
            }
        }
    }
}

// MARK: - Helper Struct

/// A placeholder type representing an intentionally empty response body from the server.
struct EmptyResponse: Codable {
    /// Creates a new empty response value.
    init() {}
}
