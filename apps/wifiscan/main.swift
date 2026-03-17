import CoreLocation
import CoreWLAN
import Foundation

struct Options {
    var json = false
    var limit: Int?
    var interfaceName: String?
}

struct NetworkRecord: Codable {
    let interface: String
    let ssid: String
    let bssid: String
    let rssi: Int
    let noise: Int
    let channel: Int
    let current: Bool
}

struct ScanOutput: Codable {
    let ok: Bool
    let interface: String?
    let availableInterfaces: [String]
    let locationServicesEnabled: Bool
    let locationStatus: String
    let currentSSID: String?
    let currentBSSID: String?
    let message: String
    let networks: [NetworkRecord]
}

enum ToolError: Error {
    case usage(String)
    case unavailable(String)
    case scanFailed(String)
}

func parseOptions(arguments: [String]) throws -> Options {
    var options = Options()
    var index = 0

    while index < arguments.count {
        let argument = arguments[index]
        switch argument {
        case "--json":
            options.json = true
        case "--limit":
            index += 1
            guard index < arguments.count, let value = Int(arguments[index]), value > 0 else {
                throw ToolError.usage("invalid value for --limit")
            }
            options.limit = value
        case "--interface":
            index += 1
            guard index < arguments.count else {
                throw ToolError.usage("missing value for --interface")
            }
            options.interfaceName = arguments[index]
        case "-h", "--help":
            throw ToolError.usage("""
            usage: wifiscan [--json] [--limit N] [--interface en0]
            """)
        default:
            throw ToolError.usage("unknown argument: \(argument)")
        }
        index += 1
    }

    return options
}

func locationStatus() -> CLAuthorizationStatus {
    let manager = CLLocationManager()
    if #available(macOS 11.0, *) {
        return manager.authorizationStatus
    }
    return CLLocationManager.authorizationStatus()
}

func locationStatusString(_ status: CLAuthorizationStatus) -> String {
    switch status {
    case .authorizedAlways:
        return "authorizedAlways"
    case .authorizedWhenInUse:
        return "authorizedWhenInUse"
    case .denied:
        return "denied"
    case .restricted:
        return "restricted"
    case .notDetermined:
        return "notDetermined"
    @unknown default:
        return "unknown"
    }
}

func writeText(_ text: String, to handle: FileHandle = .standardOutput) {
    guard let data = text.data(using: .utf8) else {
        return
    }
    try? handle.write(contentsOf: data)
}

func emit(output: ScanOutput, asJSON: Bool, to handle: FileHandle = .standardOutput) {
    if asJSON {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(output) {
            try? handle.write(contentsOf: data)
            writeText("\n", to: handle)
            return
        }
    }

    var lines: [String] = []
    lines.append(output.ok ? "Wi-Fi scan ready" : "Wi-Fi scan unavailable")
    if let interface = output.interface {
        lines.append("interface: \(interface)")
    }
    if !output.availableInterfaces.isEmpty {
        lines.append("available interfaces: \(output.availableInterfaces.joined(separator: ", "))")
    }
    lines.append("location services: \(output.locationServicesEnabled ? "enabled" : "disabled")")
    lines.append("location status: \(output.locationStatus)")
    if let currentSSID = output.currentSSID {
        let currentBSSID = output.currentBSSID ?? "unknown"
        lines.append("current network: \(currentSSID) [\(currentBSSID)]")
    }
    lines.append(output.message)

    if output.ok && !output.networks.isEmpty {
        lines.append("")
        for network in output.networks {
            let marker = network.current ? "*" : " "
            lines.append(
                "\(marker) \(network.bssid)  \(network.ssid)  \(network.rssi)dBm noise \(network.noise)dBm ch\(network.channel)"
            )
        }
    }

    writeText(lines.joined(separator: "\n") + "\n", to: handle)
}

func selectedInterface(client: CWWiFiClient, requested: String?) -> CWInterface? {
    if let requested {
        return client.interface(withName: requested)
    }
    if let current = client.interface() {
        return current
    }
    let names = Array(client.interfaceNames() ?? []).sorted()
    guard let first = names.first else {
        return nil
    }
    return client.interface(withName: first)
}

do {
    let options = try parseOptions(arguments: Array(CommandLine.arguments.dropFirst()))
    let client = CWWiFiClient.shared()
    let availableInterfaces = Array(client.interfaceNames() ?? []).sorted()
    let status = locationStatus()
    let servicesEnabled = CLLocationManager.locationServicesEnabled()

    guard let interface = selectedInterface(client: client, requested: options.interfaceName) else {
        throw ToolError.unavailable(
            """
            CoreWLAN did not expose a Wi-Fi interface. Enable Wi-Fi, then grant Location Services access to your terminal app if macOS is withholding scan access.
            """
        )
    }

    let interfaceLabel = interface.interfaceName ?? options.interfaceName ?? "unknown"
    let currentSSID = interface.ssid()
    let currentBSSID = interface.bssid()

    let results: Set<CWNetwork>
    do {
        results = try interface.scanForNetworks(withName: nil)
    } catch {
        throw ToolError.scanFailed("scan failed: \(error.localizedDescription)")
    }

    var networks = Array(results).map { network in
        NetworkRecord(
            interface: interfaceLabel,
            ssid: network.ssid ?? "<hidden>",
            bssid: network.bssid ?? "<unknown>",
            rssi: Int(network.rssiValue),
            noise: Int(network.noiseMeasurement),
            channel: Int(network.wlanChannel?.channelNumber ?? 0),
            current: (network.bssid ?? "") == (currentBSSID ?? "")
        )
    }

    networks.sort {
        if $0.current != $1.current {
            return $0.current && !$1.current
        }
        if $0.rssi != $1.rssi {
            return $0.rssi > $1.rssi
        }
        return $0.ssid.localizedCaseInsensitiveCompare($1.ssid) == .orderedAscending
    }

    if let limit = options.limit {
        networks = Array(networks.prefix(limit))
    }

    let message = networks.isEmpty
        ? "CoreWLAN returned zero nearby networks."
        : "CoreWLAN returned \(networks.count) network\(networks.count == 1 ? "" : "s")."

    emit(
        output: ScanOutput(
            ok: true,
            interface: interfaceLabel,
            availableInterfaces: availableInterfaces,
            locationServicesEnabled: servicesEnabled,
            locationStatus: locationStatusString(status),
            currentSSID: currentSSID,
            currentBSSID: currentBSSID,
            message: message,
            networks: networks
        ),
        asJSON: options.json
    )
} catch let error as ToolError {
    if case .usage(let message) = error {
        writeText(message + "\n", to: .standardError)
        exit(errorMessageCode(error))
    }

    let status = locationStatus()
    let message: String
    switch error {
    case .usage(let value):
        message = value
    case .unavailable(let value):
        message = value
    case .scanFailed(let value):
        message = value
    }

    let output = ScanOutput(
        ok: false,
        interface: nil,
        availableInterfaces: Array(CWWiFiClient.shared().interfaceNames() ?? []).sorted(),
        locationServicesEnabled: CLLocationManager.locationServicesEnabled(),
        locationStatus: locationStatusString(status),
        currentSSID: nil,
        currentBSSID: nil,
        message: message,
        networks: []
    )
    emit(output: output, asJSON: Array(CommandLine.arguments.dropFirst()).contains("--json"), to: .standardError)
    exit(errorMessageCode(error))
} catch {
    let status = locationStatus()
    let output = ScanOutput(
        ok: false,
        interface: nil,
        availableInterfaces: Array(CWWiFiClient.shared().interfaceNames() ?? []).sorted(),
        locationServicesEnabled: CLLocationManager.locationServicesEnabled(),
        locationStatus: locationStatusString(status),
        currentSSID: nil,
        currentBSSID: nil,
        message: "scan failed: \(error.localizedDescription)",
        networks: []
    )
    emit(output: output, asJSON: Array(CommandLine.arguments.dropFirst()).contains("--json"), to: .standardError)
    exit(1)
}

func errorMessageCode(_ error: ToolError) -> Int32 {
    switch error {
    case .usage:
        return 64
    case .unavailable:
        return 69
    case .scanFailed:
        return 1
    }
}
