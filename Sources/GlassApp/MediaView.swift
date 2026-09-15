import SwiftUI

struct MediaView: View {
    @ObservedObject var controller: GlassBLEController

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "wifi.circle")
                .font(.system(size: 60))
                .foregroundColor(Theme.textSecondary)
            Text("Wi-Fi Aktarımı — Yakında")
                .font(.headline)
                .foregroundColor(Theme.textPrimary)
            Text("Gözlükteki fotoğraf ve videoları Wi-Fi üzerinden telefona aktarma özelliği üzerinde çalışıyoruz.")
                .font(.caption)
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            if let count = controller.mediaFileCount {
                Text("Gözlükte \(count) dosya var")
                    .font(.subheadline)
                    .foregroundColor(Theme.accent)
            }

            Button("Medya Sayısını Sorgula") {
                controller.queryMediaCount()
            }
            .buttonStyle(.bordered)
            .padding(.top, 8)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
    }
}
