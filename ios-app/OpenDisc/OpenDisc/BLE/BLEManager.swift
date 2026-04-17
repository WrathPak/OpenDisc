@preconcurrency import CoreBluetooth
import Foundation
import Observation

enum ConnectionState: Sendable {
    case disconnected
    case scanning
    case connecting
    case connected
    case reconnecting
}

struct DiscoveredPeripheral: Identifiable {
    let id: UUID
    let peripheral: CBPeripheral
    let name: String
    var rssi: Int
    var lastSeen: Date
}

enum BLEError: LocalizedError, Identifiable {
    case bluetoothOff
    case bluetoothUnauthorized
    case connectionFailed(String)
    case connectionLost
    case characteristicNotFound
    case calibrationRejected(String)

    var id: String { localizedDescription }

    var errorDescription: String? {
        switch self {
        case .bluetoothOff:
            "Bluetooth is turned off. Enable Bluetooth in Settings."
        case .bluetoothUnauthorized:
            "Bluetooth permission is required. Enable it in Settings."
        case .connectionFailed(let msg):
            "Connection failed: \(msg)"
        case .connectionLost:
            "Connection to OpenDisc was lost. Reconnecting..."
        case .characteristicNotFound:
            "Could not find required BLE characteristics."
        case .calibrationRejected(let msg):
            "Calibration failed: \(msg)"
        }
    }
}

@MainActor @Observable
final class BLEManager: NSObject {
    // Connection
    var centralState: CBManagerState = .unknown
    var connectionState: ConnectionState = .disconnected
    var discoveredPeripherals: [DiscoveredPeripheral] = []
    var connectedPeripheral: CBPeripheral?

    // Device state
    var deviceState: DeviceState = .unknown
    var deviceStatus: DeviceStatus?
    var isCalibrated: Bool = false
    var firmwareVersion: String?

    // Live data
    var liveReading: LiveReading?
    var isLiveStreaming: Bool = false

    // Throw data
    var lastThrow: ThrowResponse?
    var throwReady: Bool = false
    var throwCount: Int = 0

    // Calibration
    var calibrationProgress: CalibrationProgress?
    var calibrationResult: CalibrationResult?
    var isCalibrating: Bool = false

    // Settings
    var deviceSettings: DeviceSettings?

    // Diagnostics
    var imuDiag: IMUDiagResponse?

    // Raw dump
    var isDumping: Bool = false
    var dumpComplete: Bool = false
    /// Progress 0...1 during active dump, nil when idle. Updated on a
    /// throttle (every ~100 ms), NOT on every frame — SwiftUI re-renders
    /// triggered by high-frequency property mutations were saturating the
    /// main run loop and starving CoreBluetooth's notification delivery.
    /// Confirmed via a Mac-side BLE client (bleak) that firmware transmits
    /// every frame correctly; the iOS app was dropping ~99% of
    /// notifications purely due to main-thread contention.
    var dumpProgress: Float?

    // Hot-path dump state. nonisolated(unsafe) because these are mutated
    // from the dedicated BLE dispatch queue (not the main actor), but
    // are only ever touched from that one serial queue — no races.
    // @ObservationIgnored keeps them out of SwiftUI's change-tracking graph.
    @ObservationIgnored nonisolated(unsafe) var dumpSamples: [DumpSampleResponse] = []
    @ObservationIgnored nonisolated(unsafe) var dumpReceivedFrames: Set<Int> = []
    @ObservationIgnored nonisolated(unsafe) var dumpDecodeFailures: Int = 0
    @ObservationIgnored nonisolated(unsafe) var dumpDecodeLastError: String?
    @ObservationIgnored nonisolated(unsafe) var dumpLastStatus: String?
    @ObservationIgnored nonisolated(unsafe) var dumpExpectedCount: Int?
    @ObservationIgnored nonisolated(unsafe) var dumpExpectedFrames: Int?
    @ObservationIgnored nonisolated(unsafe) var dumpPRNBatch: Int = 0
    @ObservationIgnored nonisolated(unsafe) var dumpLastAckSeq: Int = -1
    @ObservationIgnored nonisolated(unsafe) var dumpHighestContigSeq: Int = -1
    @ObservationIgnored nonisolated(unsafe) var dumpFrameCallCount: Int = 0
    @ObservationIgnored nonisolated(unsafe) var dumpFrameDedupCount: Int = 0
    @ObservationIgnored nonisolated(unsafe) var dumpFrameHeaderRejectCount: Int = 0
    @ObservationIgnored nonisolated(unsafe) private var dumpLastProgressPublishAt: Date = .distantPast
    /// Watchdog task that re-sends `dump_next` if a batch reply never arrives.
    @ObservationIgnored private var dumpWatchdog: Task<Void, Never>?
    /// Retries used in the current pull cycle.
    @ObservationIgnored private var dumpWatchdogRetries: Int = 0

    // Error
    var error: BLEError?

    // Private
    private var centralManager: CBCentralManager!
    private var rxCharacteristic: CBCharacteristic?
    private var wantsScan = false
    private var txCharacteristic: CBCharacteristic?
    private var pendingReconnect: CBPeripheral?
    private let decoder = JSONDecoder()

    /// Dedicated serial queue that binary dump frame processing hops onto.
    /// Delegate callbacks still land on main (so existing @MainActor state
    /// mutations work), but as soon as we see a 0xFF binary frame we
    /// dispatch it here so the main run loop is free to accept the next
    /// CoreBluetooth callback.
    nonisolated(unsafe) static let dumpProcessingQueue = DispatchQueue(
        label: "com.opendisc.ble.dump",
        qos: .userInitiated
    )

    override init() {
        super.init()
        centralManager = CBCentralManager(
            delegate: self,
            queue: .main,
            options: [CBCentralManagerOptionRestoreIdentifierKey: BLEConstants.restoreID]
        )
    }

    // MARK: - Public API

    func startScanning() {
        wantsScan = true
        guard centralState == .poweredOn else { return }
        discoveredPeripherals.removeAll()
        connectionState = .scanning
        centralManager.scanForPeripherals(
            withServices: [BLEConstants.nusServiceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
    }

    func stopScanning() {
        wantsScan = false
        centralManager.stopScan()
        if connectionState == .scanning {
            connectionState = .disconnected
        }
    }

    func connect(to peripheral: CBPeripheral) {
        stopScanning()
        connectionState = .connecting
        peripheral.delegate = self
        centralManager.connect(peripheral, options: nil)
    }

    func disconnect() {
        if let peripheral = connectedPeripheral {
            if isLiveStreaming {
                sendCommand(.liveStop)
                isLiveStreaming = false
            }
            centralManager.cancelPeripheralConnection(peripheral)
        }
        cleanupConnection()
    }

    func sendCommand(_ command: BLECommand) {
        guard let peripheral = connectedPeripheral,
              let rx = rxCharacteristic else { return }
        peripheral.writeValue(command.jsonData, for: rx, type: .withResponse)
    }

    // Convenience methods
    func requestStatus()    { sendCommand(.status) }
    func startLiveStream()  { sendCommand(.liveStart); isLiveStreaming = true }
    func stopLiveStream()   { sendCommand(.liveStop); isLiveStreaming = false }
    func armDevice()        { sendCommand(.arm) }
    func fetchThrow()       { sendCommand(.getThrow) }
    func startCalibration() { sendCommand(.calStart); isCalibrating = true }
    func stopCalibration()  { sendCommand(.calStop) }
    func getSettings()      { sendCommand(.settingsGet) }
    func requestIMUDiag()   { sendCommand(.imuDiag) }
    func dumpRaw() {
        dumpSamples.removeAll()
        dumpReceivedFrames.removeAll()
        dumpComplete = false
        dumpDecodeFailures = 0
        dumpDecodeLastError = nil
        dumpLastStatus = nil
        dumpExpectedCount = nil
        dumpExpectedFrames = nil
        dumpPRNBatch = 0
        dumpLastAckSeq = -1
        dumpHighestContigSeq = -1
        dumpFrameCallCount = 0
        dumpFrameDedupCount = 0
        dumpFrameHeaderRejectCount = 0
        dumpProgress = 0
        isDumping = true
        sendCommand(.dumpRaw)
    }

    /// Pull the next batch of binary frames from firmware. The pull-based
    /// protocol reliably stays under NimBLE's TX queue depth — iOS paces
    /// the overall transfer by only asking for the next batch after the
    /// previous one arrives.
    func dumpNext() {
        sendCommand(.dumpNext)
        armDumpWatchdog()
    }

    /// Cancel any pending watchdog and arm a fresh 3-second timer. If we
    /// don't hear back from firmware (a new binary frame OR a status update)
    /// within the window, we retry dump_next up to 3 times before giving up.
    private func armDumpWatchdog() {
        dumpWatchdog?.cancel()
        dumpWatchdog = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run { [weak self] in
                guard let self, self.isDumping else { return }
                if self.dumpWatchdogRetries < 3 {
                    self.dumpWatchdogRetries += 1
                    print("[BLE] dump watchdog: no reply — retrying dump_next (\(self.dumpWatchdogRetries)/3)")
                    self.sendCommand(.dumpNext)
                    self.armDumpWatchdog()
                } else {
                    print("[BLE] dump watchdog: giving up after 3 retries")
                    self.isDumping = false
                    self.dumpComplete = false
                    self.dumpLastStatus = "timeout"
                    self.dumpProgress = nil
                }
            }
        }
    }

    private func resetDumpWatchdog() {
        dumpWatchdog?.cancel()
        dumpWatchdog = nil
        dumpWatchdogRetries = 0
    }
    func setWifi(enabled: Bool) { sendCommand(enabled ? .wifiOn : .wifiOff) }

    func updateSettings(autoArm: Bool? = nil, triggerG: Float? = nil) {
        sendCommand(.settingsSet(autoArm: autoArm, triggerG: triggerG))
    }

    // MARK: - Private

    private func cleanupConnection() {
        connectedPeripheral = nil
        rxCharacteristic = nil
        txCharacteristic = nil
        connectionState = .disconnected
        deviceState = .unknown
        liveReading = nil
        isLiveStreaming = false
        calibrationProgress = nil
        isCalibrating = false
    }

    private func handleResponse(data: Data) {
        // First-byte discriminator: 0xFF = binary dump frame, 0x7B = JSON.
        if let first = data.first, first == 0xFF {
            handleDumpBinaryFrame(data: data)
            return
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let typeString = json["type"] as? String,
              let type = BLEResponseType(rawValue: typeString) else { return }

        switch type {
        case .status:
            if let response = try? decoder.decode(StatusResponse.self, from: data) {
                let status = DeviceStatus(from: response)
                deviceStatus = status
                deviceState = status.state
                isCalibrated = status.isCalibrated
                firmwareVersion = status.firmwareVersion
            }

        case .live:
            if let response = try? decoder.decode(LiveResponse.self, from: data) {
                liveReading = LiveReading(from: response)
                deviceState = DeviceState(from: response.state)
            }

        case .throw:
            if let response = try? decoder.decode(ThrowResponse.self, from: data) {
                lastThrow = response
                throwCount += 1
            }

        case .state:
            if let response = try? decoder.decode(StateEvent.self, from: data) {
                deviceState = DeviceState(from: response.state)
            }

        case .throwReady:
            throwReady = true
            fetchThrow()
            HapticManager.throwDetected()

        case .calProgress:
            if let response = try? decoder.decode(CalProgressResponse.self, from: data) {
                calibrationProgress = CalibrationProgress(from: response)
            }

        case .calResult:
            if let response = try? decoder.decode(CalResultResponse.self, from: data) {
                let result = CalibrationResult(from: response)
                calibrationResult = result
                isCalibrating = false
                isCalibrated = result.accepted
                if !result.accepted {
                    error = .calibrationRejected(result.message)
                }
            }

        case .settings:
            if let response = try? decoder.decode(SettingsResponse.self, from: data) {
                deviceSettings = DeviceSettings(from: response)
            }

        case .imudiag:
            if let response = try? decoder.decode(IMUDiagResponse.self, from: data) {
                imuDiag = response
            }

        case .ack:
            break

        case .dump:
            if let response = try? decoder.decode(DumpStatusResponse.self, from: data) {
                dumpLastStatus = response.status
                if response.status == "start" {
                    if let n = response.samples { dumpExpectedCount = n }
                    if let f = response.frames { dumpExpectedFrames = f }
                    if let b = response.batch { dumpPRNBatch = b }
                }
                print("[BLE] dump status=\(response.status) samples=\(response.samples ?? -1) frames=\(response.frames ?? -1) received=\(dumpSamples.count) decodeFailures=\(dumpDecodeFailures)")
                // Every status reply resets the retry counter — we heard
                // *something* from firmware.
                dumpWatchdogRetries = 0
                switch response.status {
                case "start":
                    // mode=prn  (1.1.0+): firmware blocks on our ACK every
                    //                     `batch` frames. Nothing to send
                    //                     until the first batch arrives.
                    // mode=push (1.0.9) : firmware streams without waiting;
                    //                     we just listen.
                    // mode=pull (legacy): client-driven, iOS pulls each batch.
                    if response.mode == "pull" {
                        dumpNext()
                    } else {
                        armDumpWatchdog()
                    }
                case "batch":
                    // Only seen on old pull-based firmware.
                    dumpNext()
                case "done", "no_throw":
                    isDumping = false
                    dumpComplete = response.status == "done"
                    dumpProgress = nil
                    resetDumpWatchdog()
                default:
                    break
                }
            } else {
                let snippet = String(data: data, encoding: .utf8) ?? "<binary>"
                dumpLastStatus = "undecodable"
                print("[BLE] dump status decode failed: \(snippet.prefix(120))")
            }

        case .d:
            // Legacy per-sample JSON protocol. Kept for older firmware; new
            // firmware sends a binary frame stream instead.
            do {
                let sample = try decoder.decode(DumpSampleResponse.self, from: data)
                dumpSamples.append(sample)
            } catch {
                dumpDecodeFailures += 1
                if dumpDecodeLastError == nil {
                    let snippet = String(data: data, encoding: .utf8) ?? "<binary>"
                    dumpDecodeLastError = "\(error) | payload: \(snippet.prefix(160))"
                    print("[BLE] d-sample decode failed: \(error)\n  payload: \(snippet)")
                }
            }
        }
    }

    /// Parse a 0xFF-prefixed binary dump frame. Format is:
    ///   byte 0    : 0xFF (magic)
    ///   byte 1    : version (currently 0x01)
    ///   bytes 2-3 : seq (uint16 LE)
    ///   byte 4    : count
    ///   byte 5    : reserved
    ///   bytes 6+  : `count` samples, each 10×int16 LE (i, ax..az, gx..gz, hx..hz)
    /// Off-main-actor binary-frame processor. Runs on
    /// BLEManager.dumpProcessingQueue, so SwiftUI renders on the main thread
    /// can't starve CoreBluetooth's notification delivery to this handler.
    /// Touches only nonisolated(unsafe) state; observable mutations
    /// (dumpProgress) and main-actor calls (sendCommand) are dispatched
    /// back to main explicitly.
    nonisolated func processBinaryDumpFrameBG(_ data: Data) {
        dumpFrameCallCount += 1
        guard data.count >= 6, data[0] == 0xFF, data[1] == 0x01 else {
            dumpFrameHeaderRejectCount += 1
            dumpDecodeFailures += 1
            if dumpDecodeLastError == nil {
                dumpDecodeLastError = "Bad binary header (len=\(data.count), first=\(data.first.map { String(format: "0x%02x", $0) } ?? "nil"))"
            }
            return
        }
        let seq = Int(data[2]) | (Int(data[3]) << 8)
        let count = Int(data[4])
        let expectedLen = 6 + count * 20
        guard data.count >= expectedLen else {
            dumpDecodeFailures += 1
            if dumpDecodeLastError == nil {
                dumpDecodeLastError = "Short binary frame seq=\(seq) got=\(data.count) want=\(expectedLen)"
            }
            return
        }

        if dumpReceivedFrames.contains(seq) {
            dumpFrameDedupCount += 1
            return
        }

        func readI16(_ offset: Int) -> Int16 {
            let lo = UInt16(data[offset])
            let hi = UInt16(data[offset + 1]) << 8
            return Int16(bitPattern: lo | hi)
        }

        var offset = 6
        for _ in 0..<count {
            let sample = DumpSampleResponse(
                type: "d",
                i: Int(readI16(offset)),
                ax: readI16(offset + 2),
                ay: readI16(offset + 4),
                az: readI16(offset + 6),
                gx: readI16(offset + 8),
                gy: readI16(offset + 10),
                gz: readI16(offset + 12),
                hx: readI16(offset + 14),
                hy: readI16(offset + 16),
                hz: readI16(offset + 18)
            )
            dumpSamples.append(sample)
            offset += 20
        }

        dumpReceivedFrames.insert(seq)
        while dumpReceivedFrames.contains(dumpHighestContigSeq + 1) {
            dumpHighestContigSeq += 1
        }

        // Throttled progress publish to main (the only UI-driving mutation).
        if let totalFrames = dumpExpectedFrames, totalFrames > 0 {
            let now = Date()
            if now.timeIntervalSince(dumpLastProgressPublishAt) >= 0.1 {
                dumpLastProgressPublishAt = now
                let p = Float(dumpReceivedFrames.count) / Float(totalFrames)
                DispatchQueue.main.async { [weak self] in
                    self?.dumpProgress = p
                }
            }
        }

        // PRN ACK on batch boundary — dispatch to main because sendCommand
        // must run on CoreBluetooth's (main) queue.
        if dumpPRNBatch > 0 && dumpHighestContigSeq > dumpLastAckSeq {
            let ackSeq = dumpHighestContigSeq
            let isBatchBoundary = (ackSeq + 1) % dumpPRNBatch == 0
            let isLastFrame = (dumpExpectedFrames.map { ackSeq + 1 >= $0 } ?? false)
            if isBatchBoundary || isLastFrame {
                dumpLastAckSeq = ackSeq
                DispatchQueue.main.async { [weak self] in
                    self?.sendCommand(.dumpAck(last: ackSeq))
                }
            }
        }
    }

    // ---------------------------------------------------------------------
    // Legacy main-actor binary handler. Kept so handleResponse's 0xFF guard
    // still works if a binary frame accidentally reaches that path. New
    // normal flow uses processBinaryDumpFrameBG above.
    private func handleDumpBinaryFrame(data: Data) {
        processBinaryDumpFrameBG(data)
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEManager: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        centralState = central.state
        switch central.state {
        case .poweredOn:
            if let pending = pendingReconnect {
                central.connect(pending)
                connectionState = .reconnecting
            } else if wantsScan {
                startScanning()
            }
        case .poweredOff:
            error = .bluetoothOff
            cleanupConnection()
        case .unauthorized:
            error = .bluetoothUnauthorized
        default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "Unknown"
        if let index = discoveredPeripherals.firstIndex(where: { $0.peripheral.identifier == peripheral.identifier }) {
            discoveredPeripherals[index].rssi = RSSI.intValue
            discoveredPeripherals[index].lastSeen = Date()
        } else {
            discoveredPeripherals.append(DiscoveredPeripheral(
                id: peripheral.identifier,
                peripheral: peripheral,
                name: name,
                rssi: RSSI.intValue,
                lastSeen: Date()
            ))
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedPeripheral = peripheral
        connectionState = .connected
        pendingReconnect = nil
        peripheral.delegate = self
        peripheral.discoverServices([BLEConstants.nusServiceUUID, BLEConstants.deviceInfoUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectionState = .disconnected
        self.error = .connectionFailed(error?.localizedDescription ?? "Unknown error")
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        let wasConnected = connectedPeripheral != nil
        rxCharacteristic = nil
        txCharacteristic = nil
        connectedPeripheral = nil
        liveReading = nil
        isLiveStreaming = false

        if wasConnected {
            pendingReconnect = peripheral
            connectionState = .reconnecting
            central.connect(peripheral, options: nil)
        } else {
            connectionState = .disconnected
        }
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral],
           let peripheral = peripherals.first {
            peripheral.delegate = self
            if peripheral.state == .connected {
                connectedPeripheral = peripheral
                connectionState = .connected
                peripheral.discoverServices([BLEConstants.nusServiceUUID, BLEConstants.deviceInfoUUID])
            } else {
                pendingReconnect = peripheral
                connectionState = .reconnecting
            }
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BLEManager: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        guard let characteristics = service.characteristics else { return }

        for characteristic in characteristics {
            switch characteristic.uuid {
            case BLEConstants.rxCharUUID:
                rxCharacteristic = characteristic
            case BLEConstants.txCharUUID:
                txCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            case BLEConstants.dumpCharUUID:
                // INDICATE-only characteristic for raw-dump binary frames.
                // setNotifyValue picks INDICATE when that's the only
                // property advertised by the characteristic.
                peripheral.setNotifyValue(true, for: characteristic)
            case BLEConstants.firmwareRevUUID:
                peripheral.readValue(for: characteristic)
            default:
                break
            }
        }

        if rxCharacteristic != nil && txCharacteristic != nil {
            requestStatus()
            getSettings()
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard let data = characteristic.value else { return }

        if characteristic.uuid == BLEConstants.firmwareRevUUID {
            firmwareVersion = String(data: data, encoding: .utf8)
            return
        }

        if characteristic.uuid == BLEConstants.txCharUUID {
            // Binary dump frames are time-critical: if we process them on
            // the main actor, SwiftUI re-renders or other main-thread work
            // starves CoreBluetooth's delivery pipe and notifications get
            // dropped. Dispatch to the dedicated dump queue so this method
            // returns fast and main stays available for the NEXT callback.
            if data.first == 0xFF {
                let copy = Data(data)
                Self.dumpProcessingQueue.async { [weak self] in
                    self?.processBinaryDumpFrameBG(copy)
                }
                return
            }
            handleResponse(data: data)
            return
        }

        if characteristic.uuid == BLEConstants.dumpCharUUID {
            // Legacy INDICATE channel; same background dispatch as above.
            let copy = Data(data)
            Self.dumpProcessingQueue.async { [weak self] in
                self?.processBinaryDumpFrameBG(copy)
            }
            return
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error {
            print("Notification state error: \(error.localizedDescription)")
        }
    }
}
