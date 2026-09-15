import Foundation
import CoreBluetooth
import Combine

// MARK: - Protokol sabitleri (reverse engineering ile bulundu)

enum GlassProtocol {
    // ABMate ana servis ve karakteristikleri
    static let serviceUUID = CBUUID(string: "0000fdb3-0000-1000-8000-00805f9b34fb")
    static let writeCharacteristicUUID = CBUUID(string: "0000ff17-0000-1000-8000-00805f9b34fb")
    static let notifyCharacteristicUUID = CBUUID(string: "0000ff18-0000-1000-8000-00805f9b34fb")

    // Command.java'dan önemli komut kodları (imzalı Int8 olarak)
    enum Command: Int8 {
        case glassTakePhoto = -13                  // GLASS_TAKE_PHOTO
        case glassCameraTurnOffSubsystem = -30      // GLASS_CAMERA_TURN_OFF_SUBSYSTEM
        case glassStartRecordingVideo = -28         // GLASS_START_RECORDING_VIDEO
        case glassStartRecordingAudio = -27         // GLASS_START_RECORDING_AUDIO
        case glassAiPicPush = -29                   // GLASS_AI_PIC_PUSH (cihazdan otomatik gelir)
        case glassWifiDirectAddress = -14           // GLASS_WIFI_DIRECT_ADDRESS
        case glassMediaFileCount = -17              // GLASS_MEDIA_FILE_COUNT
        case glassStorageInfo = -22                 // GLASS_STORAGE_INFO
        case glassInitFileManage = -25              // GLASS_INIT_FILE_MANAGE
        case glassSetWifiConfig = -26                // GLASS_SET_WIFI_CONFIG
        case glassDeleteFile = -21                  // GLASS_DELETE_FILE
        case commandDeviceInfo = 39                  // COMMAND_DEVICE_INFO
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

// MARK: - Otomatik segment kaydı durumları

enum RecordingState: Equatable {
    case idle
    case recording
    case stoppingForTransfer
    case transferring
}

// MARK: - Ana BLE kontrolcüsü

final class GlassBLEController: NSObject, ObservableObject {

    // Genel/log durumu
    @Published var logLines: [String] = []
    @Published var isConnected: Bool = false
    @Published var deviceName: String = "Bağlı değil"
    @Published var rssi: Int = 0

    // Cihaz bilgisi
    @Published var batteryLevel: Int? = nil
    @Published var storagePercentUsed: Int? = nil
    @Published var lastRawStorageHex: String = ""

    // Kamera / kayıt
    @Published var isRecording: Bool = false
    @Published var autoSegmentEnabled: Bool = false
    @Published var mediaFileCount: Int? = nil

    private var centralManager: CBCentralManager!
    private var glassPeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?

    private let packetBuilder = GlassPacketBuilder()
    private var pendingCommand: (GlassProtocol.Command, [UInt8])?

    private var recordingState: RecordingState = .idle
    private var storageCheckWorkItem: DispatchWorkItem?
    private var didSendHandshake = false

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

    // MARK: Bağlantı

    func startScanning() {
        guard centralManager.state == .poweredOn else {
            log("Bluetooth henüz hazır değil, state=\(centralManager.state.rawValue)")
            return
        }
        log("Taramaya başlanıyor...")
        centralManager.scanForPeripherals(withServices: [GlassProtocol.serviceUUID], options: nil)
    }

    // MARK: Temel komutlar

    func takePhoto(mode: UInt8 = 0) {
        send(command: .glassTakePhoto, payload: [mode])
    }

    func startVideoRecording() {
        send(command: .glassStartRecordingVideo, payload: [])
        DispatchQueue.main.async { self.isRecording = true }
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
        DispatchQueue.main.async { self.isRecording = false }
    }

    func queryWifiDirectAddress() {
        send(command: .glassWifiDirectAddress, payload: [])
    }

    /// InternalConnector.kt'de bağlantı kurulur kurulmaz otomatik gönderilen
    /// kapsamlı "tanışma" isteği — glassInfoToRequest dizisindeki tüm bilgi tiplerini sorar.
    /// Gözlüğün bildirim göndermeye başlaması için gerekli olabilir.
    func sendDeviceInfoHandshake() {
        let glassInfoToRequest: [Int8] = [
            1, 2, 5, 6, 9, 10, 13, 14, 22, 28, -2, 38,
            -128, -127, -124, -123, -122, -117, -115, -114, -119, -113,
            -126, -125, -106, -104, -101, -102, -109, -97, -100, -118, -93, -91, -2
        ]
        var payload: [UInt8] = []
        for infoByte in glassInfoToRequest {
            payload.append(UInt8(bitPattern: infoByte))
            payload.append(0x00)
        }
        log("El sıkışma (device info handshake) gönderiliyor — \(glassInfoToRequest.count) bilgi tipi...")
        send(command: .commandDeviceInfo, payload: payload)
    }

    func queryStorageInfo() {
        send(command: .glassStorageInfo, payload: [])
    }

    func queryBatteryLevel() {
        // COMMAND_DEVICE_INFO (39) payload formatı: [infoType, 0]
        // infoType = 1 -> INFO_DEVICE_POWER
        send(command: .commandDeviceInfo, payload: [0x01, 0x00])
    }

    func deleteFile(named fileName: String) {
        let bytes = Array(fileName.utf8)
        send(command: .glassDeleteFile, payload: bytes)
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

    /// Gözlüğü KENDİ ağımıza (Station modu) bağlanmaya zorlar - P2P el sıkışmasına gerek kalmaz.
    /// iPhone'da Kişisel Erişim Noktası açıp ssid/password'ünü buraya verebilirsin,
    /// ya da ikinizin de bağlanabileceği bir ev Wi-Fi'sını kullanabilirsin.
    func connectGlassToOurNetwork(ssid: String, password: String, channel: UInt8 = 0) {
        var payload: [UInt8] = []
        let ssidBytes = Array(ssid.utf8)
        let passwordBytes = Array(password.utf8)

        payload.append(0x01); payload.append(0x01); payload.append(0) // tag=mode, len=1, value=STATION(0)
        payload.append(0x02); payload.append(UInt8(ssidBytes.count)); payload.append(contentsOf: ssidBytes)
        payload.append(0x03); payload.append(UInt8(passwordBytes.count)); payload.append(contentsOf: passwordBytes)
        payload.append(0x04); payload.append(0x01); payload.append(channel)

        send(command: .glassSetWifiConfig, payload: payload)
    }

    // MARK: Otomatik segment kaydı (%50 doluluk -> durdur, aktar, yeniden başlat)

    func startAutoSegmentRecording() {
        guard recordingState == .idle else {
            log("Zaten kayıt döngüsü çalışıyor.")
            return
        }
        recordingState = .recording
        startVideoRecording()
        log("Otomatik segment kaydı başlatıldı.")
        scheduleStorageCheck()
    }

    func stopAutoSegmentRecording() {
        recordingState = .idle
        storageCheckWorkItem?.cancel()
        turnOffCameraSubsystem()
        log("Otomatik segment kaydı tamamen durduruldu.")
    }

    private func scheduleStorageCheck() {
        storageCheckWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self, self.recordingState == .recording else { return }
            self.log("Depolama kontrolü yapılıyor...")
            self.queryStorageInfo()
            self.scheduleStorageCheck()
        }
        storageCheckWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: workItem)
    }

    /// storagePercentUsed güncellendiğinde didUpdateValueFor'dan çağrılır.
    private func handleStorageUpdate(percentage: Int) {
        DispatchQueue.main.async { self.storagePercentUsed = percentage }
        guard recordingState == .recording, percentage >= 50 else { return }
        beginSegmentRotation()
    }

    private func beginSegmentRotation() {
        recordingState = .stoppingForTransfer
        log("=== %50 doldu, segment döndürülüyor ===")

        // 1. Mevcut kaydı durdur
        turnOffCameraSubsystem()

        // 2. Kısa bir bekleme sonrası yeni kaydı hemen başlat (kesinti minimum olsun)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self else { return }
            self.startVideoRecording()
            self.recordingState = .recording
            self.log("Yeni segment kaydı başlatıldı, eski segment aktarılacak.")
            self.scheduleStorageCheck()

            // 3. Az önce durdurulan segmenti arka planda aktar
            self.transferAndDeleteOldestSegment()
        }
    }

    private func transferAndDeleteOldestSegment() {
        log("Segment aktarımı başlatılıyor (Wi-Fi tarafı henüz tamamlanmadı — TODO).")
        // TODO: media.config sorunu çözülünce buraya:
        // 1. Dosya listesini al (queryMediaCount / gelecekteki requestFileList)
        // 2. En eski/tamamlanmış dosyayı Wi-Fi üzerinden indir
        // 3. İndirme doğrulanınca deleteFile(named:) çağır
    }

    // MARK: Gönderme

    func send(command: GlassProtocol.Command, payload: [UInt8]) {
        guard let peripheral = glassPeripheral, let writeChar = writeCharacteristic, peripheral.state == .connected else {
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
        DispatchQueue.main.async {
            self.deviceName = peripheral.name ?? "AI Glasses"
            self.rssi = RSSI.intValue
        }
        centralManager.stopScan()
        glassPeripheral = peripheral
        peripheral.delegate = self
        centralManager.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        log("Bağlandı: \(peripheral.name ?? "isimsiz"). Servisler keşfediliyor...")
        DispatchQueue.main.async { self.isConnected = true }
        peripheral.discoverServices([GlassProtocol.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        log("Bağlantı başarısız: \(error?.localizedDescription ?? "bilinmeyen hata")")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        log("Bağlantı koptu: \(error?.localizedDescription ?? "normal kapama")")
        DispatchQueue.main.async {
            self.isConnected = false
            self.deviceName = "Bağlı değil"
        }
        glassPeripheral = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        packetBuilder.reset()
        didSendHandshake = false
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
                log("Notify karakteristik özellikleri: \(characteristic.properties.rawValue)")
                peripheral.setNotifyValue(true, for: characteristic)
                log("Notify aboneliği istendi, onay bekleniyor...")
            }
        }

        if writeCharacteristic != nil, notifyCharacteristic != nil, let pending = pendingCommand {
            pendingCommand = nil
            send(command: pending.0, payload: pending.1)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            log("Notify abonelik HATASI: \(error.localizedDescription) — 2 saniye sonra tekrar denenecek")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        } else if !characteristic.isNotifying {
            log("Notify aboneliği reddedildi (isNotifying=false) — 2 saniye sonra tekrar denenecek")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        } else {
            log("Notify aboneliği ONAYLANDI ✅")
            if !didSendHandshake {
                didSendHandshake = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.sendDeviceInfoHandshake()
                }
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == GlassProtocol.notifyCharacteristicUUID, let data = characteristic.value else { return }
        let hex = data.map { String(format: "%02X", $0) }.joined(separator: " ")
        log("Bildirim alındı <- \(hex)")

        guard data.count >= 5 else { return }
        let bytes = [UInt8](data)
        let seq = bytes[0]
        let command = Int8(bitPattern: bytes[1])
        let commandType = bytes[2]
        let fragInfo = bytes[3]
        let length = bytes[4]
        log("  seq=\(seq) command=\(command) type=\(commandType) fragInfo=\(fragInfo) len=\(length)")

        // Payload'u okunabilir metin olarak göstermeyi dene (adres gibi string veriler için)
        if data.count > 5 {
            let payloadBytes = Array(bytes[5...])
            if let text = String(bytes: payloadBytes, encoding: .utf8), text.allSatisfy({ $0.isASCII && !$0.isNewline }) {
                log("  payload (metin): \(text)")
            }
        }

        // COMMAND_DEVICE_INFO (39) cevabı -> pil bilgisi ayrıştırma denemesi
        if command == 39, data.count >= 8 {
            let infoType = bytes[5]
            let infoLen = bytes[6]
            if infoType == 1, infoLen == 1 {
                let level = Int(bytes[7])
                DispatchQueue.main.async { self.batteryLevel = level }
                log("  -> Pil seviyesi: %\(level)")
            }
        }

        // GLASS_STORAGE_INFO (-22) ham verisi — format netleşince yüzde hesaplaması eklenecek
        if command == GlassProtocol.Command.glassStorageInfo.rawValue {
            DispatchQueue.main.async { self.lastRawStorageHex = hex }
            log("  -> Ham depolama bildirimi (format henüz çözülmedi): \(hex)")
        }

        // GLASS_MEDIA_FILE_COUNT (-17) cevabı
        if command == GlassProtocol.Command.glassMediaFileCount.rawValue, data.count > 5 {
            let payloadBytes = Array(bytes[5...])
            if payloadBytes.count >= 4 {
                let count = Int(payloadBytes[0]) | (Int(payloadBytes[1]) << 8) | (Int(payloadBytes[2]) << 16) | (Int(payloadBytes[3]) << 24)
                DispatchQueue.main.async { self.mediaFileCount = count }
                log("  -> Medya dosya sayısı (tahmini): \(count)")
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            log("Yazma hatası: \(error.localizedDescription)")
        }
    }
}
