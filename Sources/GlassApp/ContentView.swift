import SwiftUI

struct ContentView: View {
    @StateObject private var controller = GlassBLEController()

    var body: some View {
        VStack(spacing: 10) {
            Text(controller.isConnected ? "Bağlı ✅" : "Bağlı değil ❌")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    Button("Bağlan") { controller.startScanning() }
                    Button("Foto Çek") { controller.takePhoto() }
                    Button("Video Başlat") { controller.startVideoRecording() }
                    Button("Ses Başlat") { controller.startAudioRecording() }
                    Button("Medya Sayısı") { controller.queryMediaCount() }
                    Button("Dosya Yön. Başlat") { controller.startFileManager() }
                    Button("Kamerayı Kapat") { controller.turnOffCameraSubsystem() }
                    Button("Wi-Fi Adresi Sorgula") { controller.queryWifiDirectAddress() }
                    Button("Wi-Fi Ağı Aç") { controller.enableWifiHotspot() }
                }
                .buttonStyle(.bordered)
            }

            Divider()

            ScrollView {
                ScrollViewReader { proxy in
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(controller.logLines.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .id(index)
                        }
                    }
                    .onChange(of: controller.logLines.count) { _ in
                        if let last = controller.logLines.indices.last {
                            proxy.scrollTo(last, anchor: .bottom)
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .padding(.horizontal, 4)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
