import SwiftUI

struct ContentView: View {
    @StateObject private var controller = GlassBLEController()

    var body: some View {
        VStack(spacing: 12) {
            Text(controller.isConnected ? "Bağlı ✅" : "Bağlı değil ❌")
                .font(.headline)

            HStack {
                Button("Bağlan") {
                    controller.startScanning()
                }
                Button("Foto Çek") {
                    controller.takePhoto()
                }
                Button("Video Başlat") {
                    controller.startVideoRecording()
                }
                Button("Medya Sayısı") {
                    controller.queryMediaCount()
                }
            }
            .buttonStyle(.bordered)

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
