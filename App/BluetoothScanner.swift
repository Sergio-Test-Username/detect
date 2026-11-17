import SwiftUI
import CoreBluetooth

struct BLEDevice: Identifiable {
    let id: UUID
    var name: String
    var hasName: Bool
    var rssi: Int
    var flagged: Bool
    var maker: String?

    var proximity: String {
        if rssi > -50 { return "Very close" }
        if rssi > -65 { return "Near" }
        if rssi > -80 { return "Same room" }
        return "Far"
    }
}

final class BluetoothScanner: NSObject, ObservableObject, CBCentralManagerDelegate {
    @Published var devices: [BLEDevice] = []
    @Published var state: CBManagerState = .unknown
    @Published var isScanning = false

    private var central: CBCentralManager?
    private var table: [UUID: BLEDevice] = [:]
    private var lastPublish = Date.distantPast
    private var startedAt: Date?
    private(set) var lastDuration: Double = 0

    private static let keywords: [String] = [
        "cam", "ipc", "spy", "dvr", "nvr", "v380", "ezviz", "hikvision", "icsee", "xmeye",
        "wyze", "reolink", "tapo", "eufy", "arlo", "lorex", "annke", "pinhole", "yoosee",
        "ycc365", "wificam", "p2p", "baby", "nanny", "dashcam", "dash cam", "tuya"
    ]

    private static let makers: [UInt16: String] = [
        0x004C: "Apple",
        0x0006: "Microsoft",
        0x00E0: "Google",
        0x0075: "Samsung",
        0x0087: "Garmin",
        0x00D2: "Dialog Semiconductor",
        0x02E1: "Victron",
        0x0059: "Nordic Semiconductor",
        0x000F: "Broadcom",
        0x0171: "Amazon"
    ]

    func start() {
        table = [:]
        devices = []
        startedAt = Date()
        isScanning = true
        if central == nil {
            central = CBCentralManager(delegate: self, queue: DispatchQueue.main)
        } else {
            beginScan()
        }
    }

    func stop() {
        guard isScanning else { return }
        central?.stopScan()
        isScanning = false
        lastDuration = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        publish()
    }

    private func beginScan() {
        guard let central = central, central.state == .poweredOn, isScanning else { return }
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }

    private func publish() {
        lastPublish = Date()
        let sorted: [BLEDevice] = table.values.sorted { (a: BLEDevice, b: BLEDevice) -> Bool in
            if a.flagged != b.flagged { return a.flagged }
            return a.rssi > b.rssi
        }
        withAnimation(.spring(duration: 0.3)) {
            devices = sorted
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        state = central.state
        beginScan()
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let value = RSSI.intValue
        if value == 127 { return }
        let advName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let rawName: String? = peripheral.name ?? advName
        let displayName: String = rawName ?? "Unnamed device"

        var maker: String? = nil
        if let data = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data, data.count >= 2 {
            let bytes = [UInt8](data)
            let code = UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
            maker = BluetoothScanner.makers[code]
        }

        let lowered = displayName.lowercased()
        let flagged: Bool = rawName != nil && BluetoothScanner.keywords.contains(where: { lowered.contains($0) })

        var device: BLEDevice
        if var existing = table[peripheral.identifier] {
            existing.rssi = Int(Double(existing.rssi) * 0.7 + Double(value) * 0.3)
            if rawName != nil {
                existing.name = displayName
                existing.hasName = true
                existing.flagged = existing.flagged || flagged
            }
            if maker != nil { existing.maker = maker }
            device = existing
        } else {
            device = BLEDevice(id: peripheral.identifier, name: displayName, hasName: rawName != nil, rssi: value, flagged: flagged, maker: maker)
        }
        table[peripheral.identifier] = device

        if Date().timeIntervalSince(lastPublish) > 0.6 {
            publish()
        }
    }
}
