import SwiftUI
import RavonCore

struct RootView: View {
    @StateObject private var auth = AuthService.shared

    var body: some View {
        Group {
            if !auth.isLoaded {
                ProgressView("Загрузка...")
            } else if auth.isSignedIn {
                MerchantMainView()
            } else {
                RavonAuthFlow(role: .merchant) { /* onSignedIn */ }
            }
        }
    }
}

struct MerchantMainView: View {
    @ObservedObject private var auth = AuthService.shared
    @State private var restaurant: Restaurant?
    @State private var isLoadingRestaurant = false
    @State private var hasCheckedRestaurant = false
    @State private var roleRejectAlert = false

    var body: some View {
        Group {
            if isLoadingRestaurant || !hasCheckedRestaurant {
                ProgressView("Загрузка ресторана...")
            } else if let restaurant {
                switch restaurant.restaurantStatus {
                case .active, .paused:
                    MainTabView(restaurant: restaurant)
                case .draft:
                    OnboardingView(existingRestaurant: restaurant) { updated in
                        self.restaurant = updated
                    }
                case .closed:
                    ClosedRestaurantView()
                }
            } else {
                OnboardingView(existingRestaurant: nil) { created in
                    self.restaurant = created
                }
            }
        }
        .task { await bootstrap() }
        .alert("Доступ только для мерчантов", isPresented: $roleRejectAlert) {
            Button("OK", role: .cancel) { }
        }
    }

    private func bootstrap() async {
        if auth.userRole == nil {
            await auth.loadSession()
        }
        if let role = auth.userRole, role != .merchant {
            roleRejectAlert = true
            try? await AuthService.shared.signOut()
            return
        }
        await loadRestaurant()
    }

    private func loadRestaurant() async {
        isLoadingRestaurant = true
        defer {
            isLoadingRestaurant = false
            hasCheckedRestaurant = true
        }
        do {
            restaurant = try await SupabaseService.shared.fetchMyRestaurant()
        } catch {
            restaurant = nil
        }
    }
}
