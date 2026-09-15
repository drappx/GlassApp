import SwiftUI

struct DashboardView: View {
    @ObservedObject var controller: GlassBLEController

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                CardView {
                    HStack {
                        Circle()
                            .fill(controller.isConnected ? Theme.success : Theme.danger)
                            .frame(width: 12, height: 12)
                        VStack(alignment: .leading) {
                            Text(controller.deviceName)
                                .font(.headline)
                                .foregroundColor(Theme.textPrimary)
                            Text(controller.isConnected ? "Bağlı · RSSI \(controller.rssi)" : "Bağlı değil")
                                .font(.caption)
                                .foregroundColor(Theme.textSecondary)
                        }
                        Spacer()
                        Button(controller.isConnected ? "Yenile" : "Bağlan") {
                            controller.startScanning()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                CardView {
                    Button("El Sıkışmayı Elle Gönder") {
                        controller.sendDeviceInfoHandshake()
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                }

                HStack(spacing: 16) {
                    CardView {
                        VStack(spacing: 8) {
                            Image(systemName: "battery.75")
                                .font(.system(size: 26))
                                .foregroundColor(Theme.accent)
                            Text(controller.batteryLevel != nil ? "%\(controller.batteryLevel!)" : "—")
                                .font(.title2.bold())
                                .foregroundColor(Theme.textPrimary)
                            Text("Şarj")
                                .font(.caption)
                                .foregroundColor(Theme.textSecondary)
                            Button("Sorgula") { controller.queryBatteryLevel() }
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity)
                    }

                    CardView {
                        VStack(spacing: 8) {
                            Image(systemName: "internaldrive")
                                .font(.system(size: 26))
                                .foregroundColor(Theme.warning)
                            Text(controller.storagePercentUsed != nil ? "%\(controller.storagePercentUsed!)" : "—")
                                .font(.title2.bold())
                                .foregroundColor(Theme.textPrimary)
                            Text("Depolama")
                                .font(.caption)
                                .foregroundColor(Theme.textSecondary)
                            Button("Sorgula") { controller.queryStorageInfo() }
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }

                CardView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Hızlı İşlemler")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(Theme.textPrimary)
                        HStack(spacing: 12) {
                            BigActionButton(title: "Fotoğraf", systemImage: "camera.fill", color: Theme.accent) {
                                controller.takePhoto()
                            }
                            BigActionButton(
                                title: controller.isRecording ? "Durdur" : "Video",
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
                    }
                }

                if !controller.lastRawStorageHex.isEmpty {
                    CardView {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Ham Depolama Verisi (debug)")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(Theme.textSecondary)
                            Text(controller.lastRawStorageHex)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(Theme.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding()
        }
        .background(Theme.background.ignoresSafeArea())
    }
}
