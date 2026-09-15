import SwiftUI

struct CameraView: View {
    @ObservedObject var controller: GlassBLEController
    @State private var stationSSID: String = ""
    @State private var stationPassword: String = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                CardView {
                    VStack(spacing: 14) {
                        Image(systemName: controller.isRecording ? "record.circle.fill" : "camera.viewfinder")
                            .font(.system(size: 50))
                            .foregroundColor(controller.isRecording ? Theme.danger : Theme.accent)
                        Text(controller.isRecording ? "Kayıt Yapılıyor..." : "Kamera Hazır")
                            .font(.headline)
                            .foregroundColor(Theme.textPrimary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }

                HStack(spacing: 12) {
                    BigActionButton(title: "Fotoğraf Çek", systemImage: "camera.fill", color: Theme.accent) {
                        controller.takePhoto()
                    }
                    BigActionButton(
                        title: controller.isRecording ? "Kaydı Durdur" : "Video Başlat",
                        systemImage: controller.isRecording ? "stop.fill" : "video.fill",
                        color: controller.isRecording ? Theme.danger : Theme.success
                    ) {
                        if controller.isRecording {
                            controller.turnOffCameraSubsystem()
                        } else {
                            controller.startVideoRecording()
                        }
                    }
                }

                CardView {
                    Toggle(isOn: $controller.autoSegmentEnabled) {
                        VStack(alignment: .leading) {
                            Text("Otomatik Segment Kaydı")
                                .foregroundColor(Theme.textPrimary)
                            Text("%50 dolunca otomatik aktarıp devam eder")
                                .font(.caption)
                                .foregroundColor(Theme.textSecondary)
                        }
                    }
                    .onChange(of: controller.autoSegmentEnabled) { enabled in
                        if enabled {
                            controller.startAutoSegmentRecording()
                        } else {
                            controller.stopAutoSegmentRecording()
                        }
                    }
                }

                CardView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Ses")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(Theme.textPrimary)
                        Button("Ses Kaydını Başlat") { controller.startAudioRecording() }
                            .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                CardView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Gelişmiş")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(Theme.textPrimary)
                        Button("Dosya Yöneticisini Başlat") { controller.startFileManager() }
                            .buttonStyle(.bordered)
                        Button("Wi-Fi Adresini Sorgula") { controller.queryWifiDirectAddress() }
                            .buttonStyle(.bordered)
                        Button("Wi-Fi Ağını Aç (P2P/Hotspot modu)") { controller.enableWifiHotspot() }
                            .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                CardView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Station Modu (deneysel — P2P yerine)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(Theme.textPrimary)
                        Text("Gözlüğü kendi ağınıza (örn. Kişisel Erişim Noktası) bağlar")
                            .font(.caption)
                            .foregroundColor(Theme.textSecondary)
                        TextField("Ağ Adı (SSID)", text: $stationSSID)
                            .textFieldStyle(.roundedBorder)
                        SecureField("Şifre", text: $stationPassword)
                            .textFieldStyle(.roundedBorder)
                        Button("Gözlüğü Bu Ağa Bağla") {
                            controller.connectGlassToOurNetwork(ssid: stationSSID, password: stationPassword)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(stationSSID.isEmpty)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
        .background(Theme.background.ignoresSafeArea())
    }
}
