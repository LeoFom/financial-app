import SwiftData
import SwiftUI

@main
struct FinancialApp: App {
    let container = FinanceStore.makeContainer()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .modelContainer(container)
                .onAppear {
                    FinanceStore.seedIfNeeded(in: container.mainContext)
                }
        }
    }
}

struct RootTabView: View {
    var body: some View {
        TabView {
            OverviewScreen()
                .tabItem { Label("Финансы", systemImage: "house.fill") }

            AnalyticsScreen()
                .tabItem { Label("Аналитика", systemImage: "chart.bar.fill") }

            SettingsScreen()
                .tabItem { Label("Профиль", systemImage: "person") }
        }
        .tint(Palette.accent)
    }
}

#Preview("Огляд") {
    RootTabView()
        .modelContainer(FinanceStore.previewContainer)
}

#Preview("Огляд — темна") {
    RootTabView()
        .modelContainer(FinanceStore.previewContainer)
        .preferredColorScheme(.dark)
}
