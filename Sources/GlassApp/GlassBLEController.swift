//
//  GlassBLEController.swift
//  Marbar / ABMate gözlük için minimal, bağımsız BLE prototipi
//
//  Bu dosya AIBUDS uygulamasından bağımsız, doğrudan CoreBluetooth
//  kullanarak gözlükle konuşur. Amaç: bağlan, GLASS_TAKE_PHOTO komutunu
//  gönder, cihazın notify karakteristiğinden gelen ham byte'ları logla.
//
//  Kullanım: Bu dosyayı yeni bir Xcode projesine (iOS App, SwiftUI ya da
//  UIKit fark etmez) ekle. Info.plist'e şu iznini eklemeyi unutma:
//    NSBluetoothAlwaysUsageDescription
//  Sonra bir View/ViewController içinden:
//    let controller = GlassBLEController()
//    controller.startScanning()
//  ile başlat. Konsolu (Xcode'un alt panelindeki "debug area") izle.
//

import Foundation
import CoreBluetooth

// MARK: - Protokol sabitleri (reverse engineering ile bulundu)

enum GlassProtocol {
    // ABMate ana servis ve karakteristikleri
    static let serviceUUID = CBUUID(string: "0000fdb3-0000-1000-8000-00805f9b34fb")
    static let writeCharacteristicUUID = CBUUID(string: "0000ff17-0000-1000-8000-00805f9b34fb")
    static let notifyCharacteristicUUID = CBUUID(string: "0000ff18-0000-1000-8000-00805f9b34fb")

    // Command.java'dan önemli komut kodları (imzalı Int8 olarak)
    enum Command: Int8 {
        case glassTakePhoto = -13              // GLASS_TAKE_PHOTO — gerçek fotoğraf komutu
        case glassCameraTurnOffSubsystem = -30 // GLASS_CAMERA_TURN_OFF_SUBSYSTEM
        case glassStartRecordingVideo = -28    // GLASS_START_RECORDING_VIDEO
        case glassStartRecordingAudio = -27    // GLASS_START_RECORDING_AUDIO
        case glassAiPicPush = -29              // GLASS_AI_PIC_PUSH (cihazdan otomatik gelir)
        case glassWifiDirectAddress = -14      // GLASS_WIFI_DIRECT_ADDRESS
        case commandDeviceInfo = 39            // COMMAND_DEVICE_INFO
    }

    static let commandTypeRequest: UInt8 = 0x01

    // Varsayılan parça (fragment) payload boyutu — RequestSplitter(15)
    static let defaultMaxPayloadSize = 15
}

// MARK: - Paket oluşturucu (RequestHandler.java'nın Swift karşılığı)

final class GlassPacketBuilder {
    private var hostSeqNum: UInt8 = 0
    private let maxPayloadSize: Int

    init(maxPayloadSize: Int = GlassProtocol.defaultMaxPayloadSize) {
        self.maxPayloadSize = maxPayloadSize
    }

    func reset() {
        hostSeqNum = 0
    }

    /// Bir komutu (payload'sız ya da payload'lı) gerçek BLE paketlerine
    /// (5-byte header + chunk) böler. Java tarafındaki RequestHandler.handleRequest
    /// ile birebir aynı mantık.
    func buildPackets(command: GlassProtocol.Command, payload: [UInt8] = []) -> [[UInt8]] {
        var packets: [[UInt8]] = []

        if payload.isEmpty {
            var packet: [UInt8] = []
            packet.append(hostSeqNum)
            packet.append(UInt8(bitPattern: command.rawValue))
            packet.append(GlassProtocol.commandTypeRequest)
            packet.append(0x00) // fragInfo
            packet.append(0x00) // payloadLength
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

final class GlassBLEController: NSObject {
    private var centralManager: CBCentralManager!
    private var glassPeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?

    private let packetBuilder = GlassPacketBuilder()

    // Bekleyen komut kuyruğu (bağlantı/keşif bitmeden komut gelirse burada bekler)
    private var pendingCommand: (GlassProtocol.Command, [UInt8])?

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func startScanning() {
        guard centralManager.state == .poweredOn else {
            print("[GlassBLE] Bluetooth henüz hazır değil, state=\(centralManager.state.rawValue)")
            return
        }
        print("[GlassBLE] Taramaya başlanıyor (servis: \(GlassProtocol.serviceUUID))...")
        centralManager.scanForPeripherals(withServices: [GlassProtocol.serviceUUID], options: nil)
    }

    /// Fotoğraf çekme komutu gönder. Henüz bağlı değilsek, bağlanınca otomatik gönderilir.
    func takePhoto(mode: UInt8 = 0) {
        send(command: .glassTakePhoto, payload: [mode])
    }

    func startVideoRecording() {
        send(command: .glassStartRecordingVideo, payload: [])
    }

    func startAudioRecording() {
        send(command: .glassStartRecordingAudio, payload: [])
    }

    private func send(command: GlassProtocol.Command, payload: [UInt8]) {
        guard let peripheral = glassPeripheral,
              let writeChar = writeCharacteristic,
              peripheral.state == .connected else {
            print("[GlassBLE] Henüz bağlı değil, komut kuyruğa alındı: \(command)")
            pendingCommand = (command, payload)
            return
        }

        let packets = packetBuilder.buildPackets(command: command, payload: payload)
        for packet in packets {
            let data = Data(packet)
            print("[GlassBLE] Gönderiliyor -> \(data.map { String(format: "%02X", $0) }.joined(separator: " "))")
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
            print("[GlassBLE] Bluetooth hazır, tarama başlatılıyor.")
            startScanning()
        case .poweredOff:
            print("[GlassBLE] Bluetooth kapalı. Lütfen açın.")
        case .unauthorized:
            print("[GlassBLE] Bluetooth izni verilmemiş. Info.plist ve Ayarlar'ı kontrol edin.")
        default:
            print("[GlassBLE] Bluetooth state: \(central.state.rawValue)")
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        print("[GlassBLE] Cihaz bulundu: \(peripheral.name ?? "isimsiz") RSSI=\(RSSI)")
        centralManager.stopScan()
        glassPeripheral = peripheral
        peripheral.delegate = self
        centralManager.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("[GlassBLE] Bağlandı: \(peripheral.name ?? "isimsiz"). Servisler keşfediliyor...")
        peripheral.discoverServices([GlassProtocol.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("[GlassBLE] Bağlantı başarısız: \(error?.localizedDescription ?? "bilinmeyen hata")")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("[GlassBLE] Bağlantı koptu: \(error?.localizedDescription ?? "normal kapama")")
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
            print("[GlassBLE] Servis bulundu, karakteristikler keşfediliyor...")
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
                print("[GlassBLE] Write karakteristiği bulundu.")
            } else if characteristic.uuid == GlassProtocol.notifyCharacteristicUUID {
                notifyCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
                print("[GlassBLE] Notify karakteristiği bulundu, dinleme açıldı.")
            }
        }

        // Her iki karakteristik de hazırsa ve bekleyen bir komut varsa şimdi gönder
        if writeCharacteristic != nil, notifyCharacteristic != nil, let pending = pendingCommand {
            pendingCommand = nil
            send(command: pending.0, payload: pending.1)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == GlassProtocol.notifyCharacteristicUUID, let data = characteristic.value else { return }
        let hex = data.map { String(format: "%02X", $0) }.joined(separator: " ")
        print("[GlassBLE] Bildirim alındı <- \(hex)")

        // Ham header'ı ayrıştırmayı dene (5 byte varsa)
        if data.count >= 5 {
            let bytes = [UInt8](data)
            let seq = bytes[0]
            let command = Int8(bitPattern: bytes[1])
            let commandType = bytes[2]
            let fragInfo = bytes[3]
            let length = bytes[4]
            print("[GlassBLE]   seq=\(seq) command=\(command) type=\(commandType) fragInfo=\(fragInfo) len=\(length)")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("[GlassBLE] Yazma hatası: \(error.localizedDescription)")
        }
    }
}
