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

// MARK: - Ana BLE kontrolcüsü (artık ObservableObject — SwiftUI ekranında canlı log gösterebiliyoruz)

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
            // Çok uzamasın diye son 200 satırı tutalım
            if self.logLines.count > 200 {
                self.logLines.removeFirst(self.logLines.count - 200)
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

    private func send(command: GlassProtocol.Command, payload: [UInt8]) {
        guard let peripheral = glassPeripheral,
              let writeChar = writeCharacteristic,
              peripheral.state == .connected else {
            log("Henüz bağlı değil, komut kuyruğa alındı: \(command)")
            pendingCommand = (command, payload)
            return
        }

        let packets = packetBuilder.buildPackets(command: command, payload: payload)
        for packet in packets {
            let data = Data(packet)
            log("Gönderiliyor -> \(data.map { String(format: "%02X", $0) }.joined(separator: " "))")
            let writeType: CBCharacteristicWriteType = writeChar.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
            peripheral.writeValue(data, for: writeChar, type: writeType)
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension GlassBLEController: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            log("Bluetooth hazır, tarama başlatılıyor.")
            startScanning()
        case .poweredOff:
            log("Bluetooth kapalı. Lütfen açın.")
        case .unauthorized:
            log("Bluetooth izni verilmemiş.")
        default:
            log("Bluetooth state: \(central.state.rawValue)")
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        log("Cihaz bulundu: \(peripheral.name ?? "isimsiz") RSSI=\(RSSI)")
        centralManager.stopScan()
        glassPeripheral = peripheral
        peripheral.delegate = self
        centralManager.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        log("Bağlandı: \(peripheral.name ?? "isimsiz"). Servisler keşfediliyor...")
        isConnected = true
        peripheral.discoverServices([GlassProtocol.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        log("Bağlantı başarısız: \(error?.localizedDescription ?? "bilinmeyen hata")")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        log("Bağlantı koptu: \(error?.localizedDescription ?? "normal kapama")")
        isConnected = false
        glassPeripheral = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        packetBuilder.reset()
    }
}

// MARK: - CBPeripheralDelegate

extension GlassBLEController: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services where service.uuid == GlassProtocol.serviceUUID {
            log("Servis bulundu, karakteristikler keşfediliyor...")
            peripheral.discoverCharacteristics(
                [GlassProtocol.writeCharacteristicUUID, GlassProtocol.notifyCharacteristicUUID],
                for: service
            )
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            if characteristic.uuid == GlassProtocol.writeCharacteristicUUID {
                writeCharacteristic = characteristic
                log("Write karakteristiği bulundu.")
            } else if characteristic.uuid == GlassProtocol.notifyCharacteristicUUID {
                notifyCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
                log("Notify karakteristiği bulundu, dinleme açıldı.")
            }
        }

        if writeCharacteristic != nil, notifyCharacteristic != nil, let pending = pendingCommand {
            pendingCommand = nil
            send(command: pending.0, payload: pending.1)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == GlassProtocol.notifyCharacteristicUUID, let data = characteristic.value else { return }
        let hex = data.map { String(format: "%02X", $0) }.joined(separator: " ")
        log("Bildirim alındı <- \(hex)")

        if data.count >= 5 {
            let bytes = [UInt8](data)
            let seq = bytes[0]
            let command = Int8(bitPattern: bytes[1])
            let commandType = bytes[2]
            let fragInfo = bytes[3]
            let length = bytes[4]
            log("  seq=\(seq) command=\(command) type=\(commandType) fragInfo=\(fragInfo) len=\(length)")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            log("Yazma hatası: \(error.localizedDescription)")
        }
    }
}
