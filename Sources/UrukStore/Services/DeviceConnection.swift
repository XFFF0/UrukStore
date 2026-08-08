import Foundation
import Minimuxer
import Combine

/// Mirrors how SideStore reaches the device over a local VPN tunnel
/// (e.g. StosVPN) instead of a paired computer: minimuxer talks to a
/// fixed loopback peer address that the VPN app publishes, no App Group
/// or shared state needed — just this one well-known IP.
private let localVPNPeerIP = "10.7.0.1"

/// Plain (non-isolated) config values read from Sendable closures handed
/// to minimuxer. Kept separate from the @MainActor published state below
/// so those closures don't have to cross actor isolation to read them.
enum StaticConnectionConfig {
    static let overrideTunnelPeerIp = localVPNPeerIP
    static let remoteServerIp = localVPNPeerIP
    static let useLocalVPN = true
}

@MainActor
final class ConnectionConfig: ObservableObject {
    static let shared = ConnectionConfig()

    @Published var tunnelIfaceIp: String?
    @Published var tunnelIfaceSubnetMask: String?
    @Published var tunnelPeerIp: String?
    @Published var overrideTunnelPeerReachable = false
    @Published var remoteReachable = false
}

enum DeviceConnectionError: Error, LocalizedError {
    case noPairingFile
    case notReady(String)

    var errorDescription: String? {
        switch self {
        case .noPairingFile: return "No pairing file imported yet."
        case .notReady(let reason): return "Device not reachable: \(reason)"
        }
    }
}

/// Thin wrapper around Minimuxer (https://github.com/SideStore/minimuxer) —
/// the same library SideStore uses to talk to the device over a local VPN
/// tunnel (StosVPN) using an imported pairing file, instead of needing a
/// paired Mac/PC over USB.
@MainActor
final class DeviceConnection: ObservableObject {
    static let shared = DeviceConnection()

    @Published private(set) var isStarted = false
    @Published private(set) var udid: String?

    private let pairingFileName = "UrukStorePairingFile.mobiledevicepairing"

    private var pairingFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(pairingFileName)
    }

    var hasPairingFile: Bool {
        FileManager.default.fileExists(atPath: pairingFileURL.path)
    }

    func importPairingFile(from sourceURL: URL) throws {
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer { if didAccess { sourceURL.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: sourceURL)
        try? FileManager.default.removeItem(at: pairingFileURL)
        try data.write(to: pairingFileURL)
    }

    private func bindConnectionConfig() async {
        let config = ConnectionConfig.shared
        let binding = ConnectionConfigBinding(
            setTunnelIfaceIp: { value in Task { @MainActor in config.tunnelIfaceIp = value } },
            setTunnelPeerIp: { value in Task { @MainActor in config.tunnelPeerIp = value } },
            setTunnelIfaceSubnetMask: { value in Task { @MainActor in config.tunnelIfaceSubnetMask = value } },
            getRemoteServerIp: { StaticConnectionConfig.remoteServerIp },
            setRemoteReachable: { value in Task { @MainActor in config.remoteReachable = value } },
            getOverrideTunnelPeerIp: { StaticConnectionConfig.overrideTunnelPeerIp },
            setOverrideTunnelPeerReachable: { value in Task { @MainActor in config.overrideTunnelPeerReachable = value } },
            getConnectionMode: { StaticConnectionConfig.useLocalVPN ? .localVPN : .remoteServer }
        )
        await Minimuxer.shared.bindConnectionConfig(binding)
    }

    /// Starts minimuxer against the imported pairing file. Safe to call
    /// repeatedly — no-ops if already started for this pairing file.
    func start() async throws {
        guard hasPairingFile else { throw DeviceConnectionError.noPairingFile }
        guard let pairingString = try? String(contentsOf: pairingFileURL, encoding: .utf8) else {
            throw DeviceConnectionError.noPairingFile
        }

        await bindConnectionConfig()
        await Minimuxer.network.start()

        let mountPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DDI", isDirectory: true).path
        try? FileManager.default.createDirectory(atPath: mountPath, withIntermediateDirectories: true)

        try await Minimuxer.shared.start(pairingFile: pairingString, mountPath: mountPath)
        isStarted = true
        udid = try? await Minimuxer.shared.fetchUDID()
    }

    /// Pushes the signed .ipa's bytes to the device over AFC, then tells
    /// installation_proxy to install it — the two steps SideStore calls
    /// "yeet" and "install".
    func install(ipaData: Data, bundleIdentifier: String) async throws {
        if !isStarted { try await start() }
        try await Minimuxer.shared.yeetAppAfc(bundleId: bundleIdentifier, ipaBytes: ipaData)
        try await Minimuxer.shared.installIpa(bundleId: bundleIdentifier)
    }
}
