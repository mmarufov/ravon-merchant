import SwiftUI
import Combine
import RavonCore

@MainActor
final class MenuViewModel: ObservableObject {
    @Published var categories: [MenuCategory] = []
    @Published var items: [MenuItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    let restaurantId: UUID

    init(restaurantId: UUID) {
        self.restaurantId = restaurantId
    }

    func fetchMenu() async {
        isLoading = true

        do {
            async let cats = SupabaseService.shared.fetchMenuCategories(restaurantId: restaurantId)
            async let menuItems = SupabaseService.shared.fetchMenuItems(restaurantId: restaurantId)

            categories = try await cats.sorted { $0.sortOrder < $1.sortOrder }
            items = try await menuItems
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func items(for category: MenuCategory) -> [MenuItem] {
        items.filter { $0.categoryId == category.id }
            .sorted { $0.sortOrder < $1.sortOrder }
    }
}
