import SwiftUI
import Combine
import RavonCore

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var profile: Profile?
    @Published var restaurant: Restaurant?
    @Published var hours: [RestaurantHours] = []
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var errorMessage: String?

    let restaurantId: UUID

    init(restaurantId: UUID) {
        self.restaurantId = restaurantId
    }

    func fetchData() async {
        isLoading = true
        errorMessage = nil

        do {
            async let p = SupabaseService.shared.fetchProfile()
            async let r = SupabaseService.shared.fetchRestaurant(id: restaurantId)
            async let h = SupabaseService.shared.fetchRestaurantHours(restaurantId: restaurantId)

            profile = try await p
            restaurant = try await r
            hours = try await h
        } catch {
            errorMessage = MerchantError.message(for: error)
        }

        isLoading = false
    }

    func toggleAcceptingOrders(_ accepting: Bool) async {
        errorMessage = nil
        do {
            try await SupabaseService.shared.toggleAcceptingOrders(restaurantId: restaurantId, accepting: accepting)
            restaurant = try await SupabaseService.shared.fetchRestaurant(id: restaurantId)
        } catch {
            errorMessage = MerchantError.message(for: error)
        }
    }

    func updateRestaurant(
        name: String?,
        description: String?,
        address: String?,
        cuisineType: String?,
        deliveryFee: Double?,
        minOrderAmount: Double?,
        deliveryTimeMin: Int?,
        maxConcurrentOrders: Int?
    ) async {
        isSaving = true
        errorMessage = nil
        do {
            try await SupabaseService.shared.updateRestaurant(
                id: restaurantId,
                name: name,
                description: description,
                address: address,
                cuisineType: cuisineType,
                deliveryFee: deliveryFee,
                minOrderAmount: minOrderAmount,
                deliveryTimeMin: deliveryTimeMin,
                maxConcurrentOrders: maxConcurrentOrders
            )
            restaurant = try await SupabaseService.shared.fetchRestaurant(id: restaurantId)
        } catch {
            errorMessage = MerchantError.message(for: error)
        }
        isSaving = false
    }

    func saveHours(_ hoursList: [RestaurantHoursUpsert]) async {
        isSaving = true
        errorMessage = nil
        do {
            try await SupabaseService.shared.upsertRestaurantHours(hoursList)
            hours = try await SupabaseService.shared.fetchRestaurantHours(restaurantId: restaurantId)
        } catch {
            errorMessage = MerchantError.message(for: error)
        }
        isSaving = false
    }

    // MARK: - Restaurant Lifecycle

    func pauseRestaurant() async {
        isSaving = true
        errorMessage = nil
        do {
            try await SupabaseService.shared.pauseRestaurant(id: restaurantId)
            restaurant = try await SupabaseService.shared.fetchRestaurant(id: restaurantId)
        } catch {
            errorMessage = MerchantError.message(for: error)
        }
        isSaving = false
    }

    func resumeRestaurant() async {
        isSaving = true
        errorMessage = nil
        do {
            try await SupabaseService.shared.resumeRestaurant(id: restaurantId)
            restaurant = try await SupabaseService.shared.fetchRestaurant(id: restaurantId)
        } catch {
            errorMessage = MerchantError.message(for: error)
        }
        isSaving = false
    }

    func closeRestaurant() async {
        isSaving = true
        errorMessage = nil
        do {
            try await SupabaseService.shared.closeRestaurant(id: restaurantId)
            restaurant = try await SupabaseService.shared.fetchRestaurant(id: restaurantId)
        } catch {
            errorMessage = MerchantError.message(for: error)
        }
        isSaving = false
    }

    func fetchStats() async -> MerchantStats? {
        do {
            return try await SupabaseService.shared.fetchMerchantStats(restaurantId: restaurantId)
        } catch {
            errorMessage = MerchantError.message(for: error)
            return nil
        }
    }

    func uploadRestaurantImage(imageData: Data) async {
        isSaving = true
        errorMessage = nil
        do {
            _ = try await SupabaseService.shared.uploadRestaurantImage(
                restaurantId: restaurantId,
                imageData: imageData,
                fileExtension: "jpg"
            )
            restaurant = try await SupabaseService.shared.fetchRestaurant(id: restaurantId)
        } catch {
            errorMessage = MerchantError.message(for: error)
        }
        isSaving = false
    }

    func signOut() async {
        errorMessage = nil
        do {
            try await AuthService.shared.signOut()
        } catch {
            errorMessage = MerchantError.message(for: error)
        }
    }

}
