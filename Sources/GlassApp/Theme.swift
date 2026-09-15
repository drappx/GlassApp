import SwiftUI

enum Theme {
    static let background = Color(red: 0.07, green: 0.08, blue: 0.1)
    static let card = Color(red: 0.12, green: 0.13, blue: 0.16)
    static let accent = Color(red: 0.30, green: 0.65, blue: 1.0)
    static let success = Color(red: 0.30, green: 0.85, blue: 0.55)
    static let warning = Color(red: 0.95, green: 0.65, blue: 0.25)
    static let danger = Color(red: 0.95, green: 0.35, blue: 0.35)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.6)
}

struct CardView<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .padding(16)
            .background(Theme.card)
            .cornerRadius(18)
    }
}

struct BigActionButton: View {
    let title: String
    let systemImage: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 28))
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .cornerRadius(16)
        }
    }
}
