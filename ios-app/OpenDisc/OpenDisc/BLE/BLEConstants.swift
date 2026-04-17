@preconcurrency import CoreBluetooth

enum BLEConstants {
    nonisolated(unsafe) static let nusServiceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    nonisolated(unsafe) static let rxCharUUID     = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
    nonisolated(unsafe) static let txCharUUID     = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")
    // INDICATE-only channel dedicated to binary raw-dump frames. Separate
    // from txCharUUID so iOS subscribes to indications specifically.
    nonisolated(unsafe) static let dumpCharUUID   = CBUUID(string: "6E400004-B5A3-F393-E0A9-E50E24DCCA9E")
    nonisolated(unsafe) static let deviceInfoUUID = CBUUID(string: "180A")
    nonisolated(unsafe) static let firmwareRevUUID = CBUUID(string: "2A26")
    nonisolated(unsafe) static let batteryUUID    = CBUUID(string: "180F")
    static let deviceName     = "OpenDisc"
    static let restoreID      = "com.opendisc.central"
}
