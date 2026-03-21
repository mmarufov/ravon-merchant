import SwiftUI
import RavonCore

struct MainTabView: View {
    let restaurantId: UUID

    var body: some View {
        TabView {
            OrdersView(restaurantId: restaurantId)
                .tabItem {
                    Label("Заказы", systemImage: "list.clipboard")
                }

            MenuView(restaurantId: restaurantId)
                .tabItem {
                    Label("Меню", systemImage: "menucard")
                }

            SettingsView(restaurantId: restaurantId)
                .tabItem {
                    Label("Настройки", systemImage: "gearshape")
                }
        }
        .tint(Color.ravonRed)
    }
}
