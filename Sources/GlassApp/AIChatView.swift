import SwiftUI

struct AIChatView: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 60))
                .foregroundColor(Theme.accent)
            Text("AI Sohbet — Yakında")
                .font(.headline)
                .foregroundColor(Theme.textPrimary)
            Text("Gözlüğün kamerasından ve mikrofonundan gelen veriyle AI'a soru sorabileceksin.")
                .font(.caption)
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
    }
}
