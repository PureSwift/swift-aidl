import Binder
import Foundation

private enum ClientError: Error, CustomStringConvertible {
    case invalidArguments
    case missingService(String)

    var description: String {
        switch self {
        case .invalidArguments:
            "Usage: FrameworkClient [binder-device]"
        case let .missingService(name):
            "Binder service '\(name)' was not registered"
        }
    }
}

private func run(arguments: [String]) async throws {
    if arguments == ["--help"] || arguments == ["-h"] {
        print("Usage: FrameworkClient [binder-device]")
        print("Query the Wi-Fi and Bluetooth states using the Android framework Binder device.")
        return
    }
    guard arguments.count <= 1, arguments.first?.hasPrefix("-") != true else {
        throw ClientError.invalidArguments
    }

    let device = arguments.first ?? "/dev/binder"
    let connection = try BinderConnection(path: device)
    guard let wifi = try await connection.checkService(named: "wifi") else {
        throw ClientError.missingService("wifi")
    }
    let wifiState = try await IWifiManagerProxy(remote: wifi).getWifiEnabledState()
    print("wifi enabled state: \(wifiState)")

    guard let bluetooth = try await connection.checkService(named: "bluetooth_manager") else {
        throw ClientError.missingService("bluetooth_manager")
    }
    let bluetoothState = try await IBluetoothManagerProxy(remote: bluetooth).getState()
    print("bluetooth manager state: \(bluetoothState)")
}

do {
    try await run(arguments: Array(CommandLine.arguments.dropFirst()))
} catch {
    FileHandle.standardError.write(Data("FrameworkClient: \(error)\n".utf8))
    exit(1)
}
