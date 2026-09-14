import SwiftUI

struct ContentView: View {
    @StateObject private var controllerHolder = ControllerHolder()

    var body: some View {
        VStack(spacing: 20) {
            Text("Gözlük Kontrol")
                .font(.title)
            Button("Bağlan") {
                controllerHolder.controller.startScanning()
            }
            Button("Fotoğraf Çek") {
                controllerHolder.controller.takePhoto()
            }
            Button("Video Kaydı Başlat") {
                controllerHolder.controller.startVideoRecording()
            }
        }
        .padding()
    }
}

final class ControllerHolder: ObservableObject {
    let controller = GlassBLEController()
}

#Preview {
    ContentView()
}
