import SwiftUI
import Combine
import RavonCore

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var profile: Profile?
    @Published var restaurant: Restaurant?
    @Published var isLoading = false
    @Published var errorMessage: String?

    let restaurantId: UUID

    init(restaurantId: UUID) {
        self.restaurantId = restaurantId
    }

    func fetchData() async {
        isLoading = true

        do {
            async let p = SupabaseService.shared.fetchProfile()
            async let r = SupabaseService.shared.fetchRestaurant(id: restaurantId)

            profile = try await p
            restaurant = try await r
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func signOut() async {
        do {
            try await AuthService.shared.signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
