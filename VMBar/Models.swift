//
//  Models.swift
//  VMBar
//
//  Created by TJW on 9/21/25.
//
//  This file defines Codable data models used by VMBar to communicate with the
//  virtualization backend (e.g., VMware) over its REST API. The models mirror
//  the JSON payloads returned by and sent to the API for virtual machine details,
//  power management, networking, shared folders, and host network configuration.
//

import Foundation

// MARK: - VM Models

/// Summary information for a virtual machine as returned by list endpoints.
struct VMModel: Codable {
    /// Unique identifier of the VM.
    let id: String
    /// Filesystem path to the VM bundle or configuration.
    let path: String
    /// Optional display name of the VM (may be nil if not set).
    let displayName: String?
    /// Raw power state string as reported by the API (e.g., "poweredOn", "poweredOff").
    let powerState: String?

    enum CodingKeys: String, CodingKey {
        case id
        case path
        case displayName = "displayName"
        case powerState = "power_state"
    }
}

/// Detailed VM information commonly used for resources display/configuration.
struct VMInformation: Codable {
    /// Unique identifier of the VM.
    let id: String
    /// CPU configuration information (optional).
    let cpu: VMCPU?
    /// Memory (in MB) assigned to the VM (optional).
    let memory: VMMemory?
}

/// VM information including management and restrictions metadata.
struct VMRestrictionsInformation: Codable {
    /// Unique identifier of the VM.
    let id: String
    /// Organization that manages the VM (if under device management).
    let managedOrg: String?
    /// Integrity constraint string, if any policy applies.
    let integrityConstraint: String?
    /// CPU configuration information (optional).
    let cpu: VMCPU?
    /// Memory (in MB) assigned to the VM (optional).
    let memory: VMMemory?
    /// Optional appliance view metadata (for appliances exposing a UI/port).
    let applianceView: VMApplianceView?
    
    enum CodingKeys: String, CodingKey {
        case id
        case managedOrg
        case integrityConstraint = "integrityconstraint"
        case cpu, memory, applianceView
    }
}

/// Metadata for appliance-like VMs that expose a UI or service.
struct VMApplianceView: Codable {
    /// Author or vendor of the appliance.
    let author: String?
    /// Appliance version.
    let version: String?
    /// Port on which the appliance is accessible.
    let port: Int?
    /// Whether the appliance UI should be shown at power on ("true"/"false").
    let showAtPowerOn: String?
}

/// CPU configuration for a VM.
struct VMCPU: Codable {
    /// Number of virtual processors assigned to the VM.
    let processors: Int
}

/// Memory size in MB assigned to a VM.
typealias VMMemory = Int

/// Generic parameter with a name/value pair used by some endpoints.
struct VMParameter: Codable {
    let name: String
    let value: String
}

/// Disk mode parameter (e.g., "persistent", "nonpersistent").
struct VMDiskMode: Codable {
    let mode: String
}

/// Clone operation parameter referencing a parent VM ID.
struct VMCloneParameter: Codable {
    /// Name of the clone.
    let name: String
    /// ID of the parent VM to clone from.
    let parentId: String
}

/// Register operation parameter for registering an existing VM by path.
struct VMRegisterParameter: Codable {
    /// Desired name for the registered VM.
    let name: String
    /// Filesystem path to the VM to register.
    let path: String
}

/// Response information returned after registering a VM.
struct VMRegistrationInformation: Codable {
    /// Newly registered VM ID.
    let id: String
    /// Path of the registered VM.
    let path: String
}

// MARK: - Power Management Models

/// Represents the VM's power state as returned by the API.
struct VMPowerState: Codable {
    /// Raw power state string ("poweredOn", "poweredOff", "suspended", "paused").
    let powerState: String
    
    enum CodingKeys: String, CodingKey {
        case powerState = "power_state"
    }
    
    /// True if the VM is currently powered on.
    var isPoweredOn: Bool {
        return powerState == "poweredOn"
    }
    
    /// True if the VM is currently powered off.
    var isPoweredOff: Bool {
        return powerState == "poweredOff"
    }
    
    /// True if the VM is currently suspended.
    var isSuspended: Bool {
        return powerState == "suspended"
    }
    
    /// True if the VM is currently paused.
    var isPaused: Bool {
        return powerState == "paused"
    }
}

/// Supported power operations that can be invoked via the API.
enum VMPowerOperation: String {
    case on = "on"
    case off = "off"
    case shutdown = "shutdown"
    case suspend = "suspend"
    case pause = "pause"
    case unpause = "unpause"
}

// MARK: - Network Adapter Models

/// A single virtual NIC device attached to a VM.
struct NICDevice: Codable {
    /// Adapter index (starting at 0 or 1 depending on backend).
    let index: Int
    /// Backing type: "custom", "bridged", "nat", or "hostonly".
    let type: String
    /// Name of the vmnet (for "custom" type) or the resolved vmnet backing.
    let vmnet: String
    /// MAC address assigned to the NIC.
    let macAddress: String
}

/// Collection of NICs for a VM, including a count.
struct NICDevices: Codable {
    /// Number of NICs attached.
    let num: Int
    /// Array of NIC device descriptors.
    let nics: [NICDevice]
}

/// Parameter used to configure a NIC's network backing.
struct NICDeviceParameter: Codable {
    /// Backing type: "custom", "bridged", "nat", or "hostonly".
    let type: String // custom, bridged, nat, hostonly
    /// For "custom" type, the vmnet name to use; may be empty for other types.
    let vmnet: String
}

/// A single IP address string returned by some endpoints.
struct VMIPAddress: Codable {
    /// IP address (IPv4 or IPv6) as a string.
    let ip: String
}

/// Network stack information for a single NIC.
struct NicIpStack: Codable {
    /// MAC address of the NIC this stack refers to.
    let mac: String
    /// List of IP addresses assigned to the NIC (if any).
    let ip: [String]?
    /// DNS configuration for the NIC.
    let dns: DnsConfig?
    /// WINS configuration for the NIC (primarily for legacy Windows guests).
    let wins: WinsConfig?
    /// DHCPv4 configuration for the NIC.
    let dhcp4: DhcpConfig?
    /// DHCPv6 configuration for the NIC.
    let dhcp6: DhcpConfig?
}

/// Aggregated network stack information for all NICs.
struct NicIpStackAll: Codable {
    /// Per-NIC IP stack details.
    let nics: [NicIpStack]?
    /// Routing table entries for the guest.
    let routes: [RouteEntry]?
    /// Global DNS configuration.
    let dns: DnsConfig?
    /// Global WINS configuration.
    let wins: WinsConfig?
    /// Global DHCPv4 configuration.
    let dhcpv4: DhcpConfig?
    /// Global DHCPv6 configuration.
    let dhcpv6: DhcpConfig?
}

/// DNS configuration for a guest.
struct DnsConfig: Codable {
    /// Hostname of the guest.
    let hostname: String?
    /// Domain name of the guest.
    let domainname: String?
    /// DNS server IP addresses.
    let server: [String]?
    /// DNS search domains.
    let search: [String]?
}

/// WINS configuration for a guest.
struct WinsConfig: Codable {
    /// Primary WINS server IP.
    let primary: String
    /// Secondary WINS server IP.
    let secondary: String
}

/// DHCP configuration for a guest.
struct DhcpConfig: Codable {
    /// Whether DHCP is enabled.
    let enabled: Bool
    /// Backend-specific setting string (e.g., "dhcp", "static").
    let setting: String
}

/// A single route entry from the guest routing table.
struct RouteEntry: Codable {
    /// Destination network (CIDR base address).
    let dest: String
    /// Prefix length of the destination network.
    let prefix: Int
    /// Next hop IP address (optional for directly connected routes).
    let nexthop: String?
    /// Interface index associated with the route.
    let interface: Int
    /// Route type (backend-specific).
    let type: Int
    /// Route metric (lower is preferred).
    let metric: Int
}

// MARK: - Shared Folder Models

/// A shared folder mapping from host to guest.
struct SharedFolder: Codable {
    /// Folder identifier in the backend.
    let folderId: String
    /// Absolute host path to the shared folder.
    let hostPath: String
    /// Flags bitmask controlling access (e.g., 4 indicates read-write).
    let flags: Int
    
    enum CodingKeys: String, CodingKey {
        case folderId = "folder_id"
        case hostPath = "host_path"
        case flags
    }
}

/// Parameter for creating or updating a shared folder.
struct SharedFolderParameter: Codable {
    /// Absolute host path to share.
    let hostPath: String
    /// Flags bitmask controlling access (e.g., 4 indicates read-write).
    let flags: Int
    
    enum CodingKeys: String, CodingKey {
        case hostPath = "host_path"
        case flags
    }
}

// MARK: - Host Network Models

/// A host vmnet network definition (bridged, NAT, or host-only).
struct Network: Codable {
    /// Network name (e.g., "vmnet1", "vmnet8", or a bridged interface name).
    let name: String
    /// Network type: "bridged", "nat", or "hostOnly".
    let type: String // bridged, nat, hostOnly
    /// Whether DHCP is enabled on the vmnet ("true" or "false").
    let dhcp: String // "true" or "false"
    /// Subnet address (e.g., "192.168.56.0").
    let subnet: String
    /// Subnet mask (e.g., "255.255.255.0").
    let mask: String
    
    /// Convenience boolean derived from the `dhcp` string.
    var isDHCPEnabled: Bool {
        return dhcp == "true"
    }
}

/// A collection of host networks, including a count.
struct Networks: Codable {
    /// Number of vmnets defined.
    let num: Int
    /// Array of vmnet definitions.
    let vmnets: [Network]
}

/// Parameter to create a new vmnet of type NAT or host-only.
struct CreateVmnetParameter: Codable {
    /// Desired vmnet name (e.g., "vmnet9").
    let name: String
    /// Type of vmnet to create: "nat" or "hostOnly".
    let type: String? // nat, hostOnly
}

/// A single port forwarding rule on a NAT vmnet.
struct Portforward: Codable {
    /// Host-side port to forward.
    let port: Int
    /// Transport protocol: "tcp" or "udp".
    let `protocol`: String // tcp, udp
    /// Optional human-readable description.
    let desc: String
    /// Guest endpoint for the forwarding rule.
    let guest: GuestPortforward
}

/// Guest endpoint for a port forwarding rule.
struct GuestPortforward: Codable {
    /// Guest IP address receiving the forwarded traffic.
    let ip: String
    /// Guest port receiving the forwarded traffic.
    let port: Int
}

/// A collection of port forwarding rules, including a count.
struct Portforwards: Codable {
    /// Number of port forwarding rules.
    let num: Int
    /// Array of port forwarding definitions.
    let portForwardings: [Portforward]
    
    enum CodingKeys: String, CodingKey {
        case num
        case portForwardings = "port_forwardings"
    }
}

/// Parameter to create or update a port forwarding rule.
struct PortforwardParameter: Codable {
    /// Guest IP address to forward to.
    let guestIp: String
    /// Guest port to forward to.
    let guestPort: Int
    /// Optional description for the rule.
    let desc: String?
}

/// Mapping between a MAC address and an assigned IP on a vmnet.
struct MACToIP: Codable {
    /// vmnet name where the mapping applies.
    let vmnet: String
    /// MAC address of the guest.
    let mac: String
    /// IP address assigned to the MAC on the vmnet.
    let ip: String
}

/// A collection of MAC-to-IP mappings, including a count.
struct MACToIPs: Codable {
    /// Number of mappings.
    let num: Int
    /// Array of MAC-to-IP mappings.
    let mactoips: [MACToIP]
}

/// Parameter to assign a static IP to a given MAC on a vmnet.
struct MacToIPParameter: Codable {
    /// IP address to assign.
    let ip: String
    
    enum CodingKeys: String, CodingKey {
        // The API expects an uppercase "IP" key.
        case ip = "IP"
    }
}

// MARK: - Helper Extensions

extension VMModel {
    /// True if the VM is currently powered on.
    var isPoweredOn: Bool {
        return powerState == "poweredOn"
    }
    
    /// True if the VM is currently powered off.
    var isPoweredOff: Bool {
        return powerState == "poweredOff"
    }
    
    /// True if the VM is currently suspended.
    var isSuspended: Bool {
        return powerState == "suspended"
    }
    
    /// A user-friendly title favoring `displayName` over `id`.
    var displayTitle: String {
        return displayName ?? id
    }
}

extension NICDevice {
    /// True if the NIC backing is "custom".
    var isCustom: Bool { type == "custom" }
    /// True if the NIC backing is "bridged".
    var isBridged: Bool { type == "bridged" }
    /// True if the NIC backing is "nat".
    var isNAT: Bool { type == "nat" }
    /// True if the NIC backing is "hostonly".
    var isHostOnly: Bool { type == "hostonly" }
}

extension Network {
    /// True if the vmnet is bridged.
    var isBridged: Bool { type == "bridged" }
    /// True if the vmnet is NAT.
    var isNAT: Bool { type == "nat" }
    /// True if the vmnet is host-only.
    var isHostOnly: Bool { type == "hostOnly" }
}

extension SharedFolder {
    /// True if the shared folder is read-write (flags == 4).
    var isReadWrite: Bool { flags == 4 }
}

// MARK: - Convenience Initializers

extension NICDeviceParameter {
    /// Create a bridged NIC parameter.
    static func bridged() -> NICDeviceParameter {
        return NICDeviceParameter(type: "bridged", vmnet: "")
    }
    
    /// Create a NAT NIC parameter.
    static func nat() -> NICDeviceParameter {
        return NICDeviceParameter(type: "nat", vmnet: "")
    }
    
    /// Create a host-only NIC parameter.
    static func hostOnly() -> NICDeviceParameter {
        return NICDeviceParameter(type: "hostonly", vmnet: "")
    }
    
    /// Create a custom NIC parameter bound to a specific vmnet.
    static func custom(vmnet: String) -> NICDeviceParameter {
        return NICDeviceParameter(type: "custom", vmnet: vmnet)
    }
}

extension SharedFolderParameter {
    /// Convenience factory for a read-write shared folder (flags = 4).
    static func readWrite(hostPath: String) -> SharedFolderParameter {
        return SharedFolderParameter(hostPath: hostPath, flags: 4)
    }
}

extension PortforwardParameter {
    /// Initialize a port forwarding parameter with optional description.
    init(guestIp: String, guestPort: Int, description: String? = nil) {
        self.guestIp = guestIp
        self.guestPort = guestPort
        self.desc = description
    }
}

extension CreateVmnetParameter {
    /// Create a NAT vmnet creation parameter.
    static func nat(name: String) -> CreateVmnetParameter {
        return CreateVmnetParameter(name: name, type: "nat")
    }
    
    /// Create a host-only vmnet creation parameter.
    static func hostOnly(name: String) -> CreateVmnetParameter {
        return CreateVmnetParameter(name: name, type: "hostOnly")
    }
}
