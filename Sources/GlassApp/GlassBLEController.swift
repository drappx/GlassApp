import Foundation
import CoreBluetooth
import Combine

// MARK: - Protokol sabitleri

enum GlassProtocol {
    static let serviceUUID = CBUUID(string: "0000fdb3-0000-1000-8000-00805f9b34fb")
    static let writeCharacteristicUUID = CBUUID(string: "0000ff17-0000-1000-8000-00805f9b34fb")
    static let notifyCharacteristicUUID = CBUUID(string: "0000ff18-0000-1000-8000-00805f9b34fb")

    enum Command: Int8 {
        case glassTakePhoto = -13
        case glassCameraTurnOffSubsystem = -30
        case glassStartRecordingVideo = -28
        case glassStartRecordingAudio = -27
        case glassAiPicPush = -29
        case glassWifiDirectAddress = -14
        case glassMediaFileCount = -17
        case glassInitFileManage = -25
        case glassSetWifiConfig = -26
        case commandDeviceInfo = 39
    }

    static let commandTypeRequest: UInt8 = 0x01
    static let defaultMaxPayloadSize = 15
}

// MARK: - Paket oluşturucu

final class GlassPacketBuilder {
    private var hostSeqNum: UInt8 = 0
    private let maxPayloadSize: Int

    init(maxPayloadSize: Int = GlassProtocol.defaultMaxPayloadSize) {
        self.maxPayloadSize = maxPayloadSize
    }

    func reset() {
        hostSeqNum = 0
    }

    func buildPackets(command: GlassProtocol.Command, payload: [UInt8] = []) -> [[UInt8]] {
        var packets: [[UInt8]] = []

        if payload.isEmpty {
            var packet: [UInt8] = []
            packet.append(hostSeqNum)
            packet.append(UInt8(bitPattern: command.rawValue))
            packet.append(GlassProtocol.commandTypeRequest)
            packet.append(0x00)
            packet.append(0x00)
            packets.append(packet)
            hostSeqNum = (hostSeqNum &+ 1) & 0x0F
        } else {
            let fragNum = Int(ceil(Double(payload.count) / Double(maxPayloadSize)))
            for fragIndex in 0..<fragNum {
                let start = fragIndex * maxPayloadSize
                let end = min(start + maxPayloadSize, payload.count)
                let chunk = Array(payload[start..<end])
                let fragInfo = UInt8((((fragNum - 1) << 4) & 0xF0) | (fragIndex & 0x0F))

                var packet: [UInt8] = []
                packet.append(hostSeqNum)
                packet.append(UInt8(bitPattern: command.rawValue))
                packet.append(GlassProtocol.commandTypeRequest)
                packet.append(fragInfo)
                packet.append(UInt8(chunk.count))
                packet.append(contentsOf: chunk)
                packets.append(packet)

                hostSeqNum = (hostSeqNum &+ 1) & 0x0F
            }
        }

        return packets
    }
}

// MARK: - Ana BLE kontrolcüsü

final class GlassBLEController: NSObject, ObservableObject {
    @Published var logLines: [String] = []
    @Published var isConnected: Bool = false

    private var centralManager: CBCentralManager!
    private var glassPeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?

    private let packetBuilder = GlassPacketBuilder()
    private var pendingCommand: (GlassProtocol.Command, [UInt8])?

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    private func log(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let line = "[\(timestamp)] \(message)"
        print(line)
        DispatchQueue.main.async {
            self.logLines.append(line)
            if self.logLines.count > 300 {
                self.logLines.removeFirst(self.logLines.count - 300)
            }
        }
    }

    func startScanning() {
        guard centralManager.state == .poweredOn else {
            log("Bluetooth henüz hazır değil, state=\(centralManager.state.rawValue)")
            return
        }
        log("Taramaya başlanıyor...")
        centralManager.scanForPeripherals(withServices: [GlassProtocol.serviceUUID], options: nil)
    }

    // MARK: Komutlar

    func takePhoto(mode: UInt8 = 0) {
        send(command: .glassTakePhoto, payload: [mode])
    }

    func startVideoRecording() {
        send(command: .glassStartRecordingVideo, payload: [])
    }

    func startAudioRecording() {
        send(command: .glassStartRecordingAudio, payload: [])
    }

    func queryMediaCount() {
        send(command: .glassMediaFileCount, payload: [])
    }

    func startFileManager() {
        send(command: .glassInitFileManage, payload: [])
    }

    func turnOffCameraSubsystem() {
        send(command: .glassCameraTurnOffSubsystem, payload: [])
    }

    func queryWifiDirectAddress() {
        send(command: .glassWifiDirectAddress, payload: [])
    }

    /// Gözlüğü kendi açık Wi-Fi ağını yayınlamaya zorlar (AIBUDS'ın yaptığı gibi)
    func enableWifiHotspot(ssid: String = "AiGlassDb_\(Int.random(in: 0..<10000))", channel: UInt8 = 0) {
        var payload: [UInt8] = []
        let ssidBytes = Array(ssid.utf8)
        let passwordBytes: [UInt8] = [] // AIBUDS de boş şifre kullanıyor

        payload.append(0x01); payload.append(0x01); payload.append(1) // tag=mode, len=1, value=AP
        payload.append(0x02); payload.append(UInt8(ssidBytes.count)); payload.append(contentsOf: ssidBytes)
        payload.append(0x03); payload.append(UInt8(passwordBytes.count)); payload.append(contentsOf: passwordBytes)
        payload.append(0x04); payload.append(0x01); payload.append(channel)

        send(command: .glassSetWifiConfig, payload: payload)
    }

    private func send(command: GlassProtocol.Command, payload: [UInt8]) {
        guard let peripheral = glassPeripheral,
              let
