import SwiftUI
import RavonCore

struct MainTabView: View {
    let restaurant: Restaurant

    var body: some View {
        TabView {
            DashboardView(restaurant: restaurant)
                .tabItem {
                    Label("Дашборд", systemImage: "chart.bar")
                }

            OrdersView(restaurantId: restaurant.id)
                .tabItem {
                    Label("Заказы", systemImage: "list.clipboard")
                }

            MenuView(restaurantId: restaurant.id)
                .tabItem {
                    Label("Меню", systemImage: "menucard")
                }

            SettingsView(restaurantId: restaurant.id)
                .tabItem {
                    Label("Настройки", systemImage: "gearshape")
                }
        }
        .tint(Color.ravonRed)
    }
}
