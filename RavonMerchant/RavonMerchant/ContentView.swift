import SwiftUI
import RavonCore

struct ContentView: View {
    @ObservedObject private var auth = AuthService.shared
    @AppStorage("selectedRestaurantId") private var selectedRestaurantId: String?

    var body: some View {
        Group {
            if !auth.isLoaded {
                ProgressView("Загрузка...")
            } else if !auth.isSignedIn {
                LoginView()
            } else if let idString = selectedRestaurantId,
                      let id = UUID(uuidString: idString) {
                MainTabView(restaurantId: id)
            } else {
                RestaurantPickerView { id in
                    selectedRestaurantId = id.uuidString
                }
            }
        }
        .task {
            await auth.loadSession()
        }
    }
}
