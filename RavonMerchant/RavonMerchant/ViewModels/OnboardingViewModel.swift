import SwiftUI
import Combine
import PhotosUI
import RavonCore

@MainActor
final class OnboardingViewModel: ObservableObject {
    @Published var currentStep = 1
    @Published var restaurant: Restaurant?
    @Published var progress: OnboardingProgress?
    @Published var suggestedCategories: [String] = []
    @Published var createdCategories: [MenuCategory] = []
    @Published var createdItems: [MenuItem] = []
    @Published var previewData: (restaurant: Restaurant, categories: [MenuCategory], items: [MenuItem])?
    @Published var isLoading = false
    @Published var errorMessage: String?

    let totalSteps = 6

    // MARK: - Step 1: Create Restaurant

    func createRestaurant(
        name: String,
        cuisineType: String,
        address: String,
        deliveryFee: Double,
        minOrderAmount: Double,
        deliveryTimeMin: Int
    ) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // Belt-and-suspenders defaults so the consumer app never sees NULL/empty
        // values that would break decoding of non-optional Restaurant fields.
        let trimmedCuisine = cuisineType.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedCuisine = trimmedCuisine.isEmpty ? "Разное" : trimmedCuisine
        let resolvedDeliveryFee = max(0, deliveryFee)
        let resolvedMinOrder = max(0, minOrderAmount)
        let resolvedDeliveryTime = deliveryTimeMin > 0 ? deliveryTimeMin : 30

        do {
            let insert = RestaurantInsert(
                name: name,
                description: nil,
                cuisineType: resolvedCuisine,
                address: address,
                latitude: nil,
                longitude: nil,
                deliveryFee: resolvedDeliveryFee,
                minOrderAmount: resolvedMinOrder,
                deliveryTimeMin: resolvedDeliveryTime
            )
            restaurant = try await SupabaseService.shared.createRestaurant(insert)
            suggestedCategories = MenuCategoryTemplate.suggestions(for: resolvedCuisine)
            currentStep = 2
        } catch {
            guard isAlreadyHasRestaurant(error) else {
                errorMessage = MerchantError.message(for: error)
                return
            }
            // Merchant already has a restaurant — fetch it and resume where they left off.
            do {
                if let existing = try await SupabaseService.shared.fetchMyRestaurant() {
                    await resumeOnboarding(for: existing)
                } else {
                    errorMessage = MerchantError.message(for: error)
                }
            } catch {
                // A failed refetch used to fall through to nothing at all: the Create
                // button simply went quiet and the merchant was stuck on step 1.
                errorMessage = MerchantError.message(for: error)
            }
        }
    }

    // MARK: - Step 2: Upload Restaurant Photo

    func uploadRestaurantPhoto(imageData: Data) async {
        guard let restaurant else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let url = try await SupabaseService.shared.uploadRestaurantImage(
                restaurantId: restaurant.id,
                imageData: imageData,
                fileExtension: "jpg"
            )
            // Refresh restaurant to pick up new image URL
            self.restaurant = try await SupabaseService.shared.fetchMyRestaurant()
            _ = url
        } catch {
            errorMessage = MerchantError.message(for: error)
        }
    }

    func skipPhoto() {
        currentStep = 3
    }

    // MARK: - Step 3: Create Categories

    func createCategories(names: [String]) async {
        guard let restaurant else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            for (index, name) in names.enumerated() {
                let insert = MenuCategoryInsert(
                    restaurantId: restaurant.id,
                    name: name,
                    sortOrder: index
                )
                let category = try await SupabaseService.shared.createMenuCategory(insert)
                createdCategories.append(category)
            }
            currentStep = 4
        } catch {
            errorMessage = MerchantError.message(for: error)
        }
    }

    // MARK: - Step 4: Create Menu Items

    func createMenuItem(
        categoryId: UUID,
        name: String,
        price: Double,
        description: String?,
        imageData: Data?
    ) async {
        guard let restaurant else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            var imageUrl: String?
            let sortOrder = createdItems.filter { $0.categoryId == categoryId }.count

            let insert = MenuItemInsert(
                restaurantId: restaurant.id,
                categoryId: categoryId,
                name: name,
                description: description,
                price: price,
                imageUrl: nil,
                isAvailable: true,
                sortOrder: sortOrder
            )
            let item = try await SupabaseService.shared.createMenuItem(insert)

            if let imageData {
                imageUrl = try await SupabaseService.shared.uploadMenuItemImage(
                    menuItemId: item.id,
                    imageData: imageData,
                    fileExtension: "jpg"
                )
                _ = imageUrl
            }

            createdItems.append(item)
        } catch {
            errorMessage = MerchantError.message(for: error)
        }
    }

    // MARK: - Step 3: Delete Category

    func deleteCategory(id: UUID) async {
        do {
            try await SupabaseService.shared.deleteMenuCategory(id: id)
            createdCategories.removeAll { $0.id == id }
        } catch {
            errorMessage = MerchantError.message(for: error)
        }
    }

    // MARK: - Step 5: Save Hours

    func saveHours(_ entries: [(dayOfWeek: Int, openingTime: String, closingTime: String, isClosed: Bool)]) async {
        guard let restaurant else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let upserts = entries.map { entry in
                RestaurantHoursUpsert(
                    restaurantId: restaurant.id,
                    dayOfWeek: entry.dayOfWeek,
                    openingTime: entry.openingTime,
                    closingTime: entry.closingTime,
                    isClosed: entry.isClosed
                )
            }
            try await SupabaseService.shared.upsertRestaurantHours(upserts)
            currentStep = 6
        } catch {
            errorMessage = MerchantError.message(for: error)
        }
    }

    // MARK: - Step 6: Preview & Go Live

    func fetchPreview() async {
        guard let restaurant else { return }
        do {
            let (r, cats, menuItems) = try await SupabaseService.shared.fetchRestaurantPreview(restaurantId: restaurant.id)
            previewData = (r, cats, menuItems)
        } catch {
            errorMessage = MerchantError.message(for: error)
        }
    }

    func refreshProgress() async {
        do {
            progress = try await SupabaseService.shared.fetchOnboardingProgress()
        } catch {
            errorMessage = MerchantError.message(for: error)
        }
    }

    func activateRestaurant() async {
        guard let restaurant else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await SupabaseService.shared.activateRestaurant(id: restaurant.id)
            self.restaurant = try await SupabaseService.shared.fetchMyRestaurant()
        } catch {
            errorMessage = MerchantError.message(for: error)
        }
    }

    // MARK: - Resume onboarding

    func resumeOnboarding(for restaurant: Restaurant) async {
        self.restaurant = restaurant
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let progress = try await SupabaseService.shared.fetchOnboardingProgress()
            self.progress = progress

            // Load existing categories
            createdCategories = try await SupabaseService.shared.fetchMenuCategories(restaurantId: restaurant.id)
            createdItems = try await SupabaseService.shared.fetchAllMenuItems(restaurantId: restaurant.id)
            suggestedCategories = MenuCategoryTemplate.suggestions(for: restaurant.cuisineType)

            // Determine which step to resume at
            if createdCategories.isEmpty {
                currentStep = 3
            } else if createdItems.isEmpty {
                currentStep = 4
            } else {
                currentStep = 6
            }
        } catch {
            errorMessage = MerchantError.message(for: error)
        }
    }

    // MARK: - Error classification

    /// Typed replacement for `desc.contains("already")`.
    ///
    /// That substring match was not just cosmetic — it was *control flow*: it decided
    /// whether to reroute the wizard into resume mode. Any unrelated failure whose
    /// description happened to contain "already" sent the merchant somewhere else, and
    /// since `ServiceError.localizedDescription` is the Russian text, the
    /// `"merchantAlreadyHasRestaurant"` branch beside it could never match at all.
    private func isAlreadyHasRestaurant(_ error: Error) -> Bool {
        if let service = error as? ServiceError,
           case .merchantAlreadyHasRestaurant = service {
            return true
        }
        // The server's own token, for the case where the error arrives untyped.
        return String(describing: error).uppercased().contains("MERCHANT_ALREADY_HAS_RESTAURANT")
    }
}
