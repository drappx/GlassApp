import SwiftUI

struct ContentView: View {
    @StateObject private var controller = GlassBLEController()
    @State private var showDevLog = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            TabView {
                DashboardView(controller: controller)
                    .tabItem { Label("Ana Sayfa", systemImage: "house.fill") }

                CameraView(controller: controller)
                    .tabItem { Label("Kamera", systemImage: "camera.fill") }

                MediaView(controller: controller)
                    .tabItem { Label("Medya", systemImage: "photo.on.rectangle") }

                AIChatView()
                    .tabItem { Label("AI", systemImage: "sparkles") }
            }
            .tint(Theme.accent)
            .onAppear {
                UITabBar.appearance().backgroundColor = UIColor(Theme.card)
            }

            Button {
                showDevLog = true
            } label: {
                Image(systemName: "ladybug.fill")
                    .foregroundColor(Theme.textSecondary)
                    .padding(10)
            }
        }
        .sheet(isPresented: $showDevLog) {
            NavigationView {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(controller.logLines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(Theme.textPrimary)
                        }
                    }
                    .padding()
                }
                .background(Theme.background.ignoresSafeArea())
                .navigationTitle("Geliştirici Log")
                .navigationBarItems(trailing: Button("Kapat") { showDevLog = false })
            }
        }
    }
}

#Preview {
    ContentView()
}
