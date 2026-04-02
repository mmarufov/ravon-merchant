import SwiftUI
import RavonCore

struct ContentView: View {
    @ObservedObject private var auth = AuthService.shared
    @State private var restaurant: Restaurant?
    @State private var isLoadingRestaurant = false
    @State private var hasCheckedRestaurant = false

    var body: some View {
        Group {
            if !auth.isLoaded {
                ProgressView("Загрузка...")
            } else if !auth.isSignedIn {
                LoginView()
                    .onChange(of: auth.isSignedIn) { _, signedIn in
                        if signedIn {
                            hasCheckedRestaurant = false
                            Task { await loadRestaurant() }
                        }
                    }
            } else if isLoadingRestaurant || !hasCheckedRestaurant {
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
        .task {
            await auth.loadSession()
            if auth.isSignedIn {
                await loadRestaurant()
            }
        }
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
