import SwiftUI
import Combine
import RavonCore

@MainActor
final class MenuViewModel: ObservableObject {
    @Published var categories: [MenuCategory] = []
    @Published var items: [MenuItem] = []
    @Published var modifierGroups: [ModifierGroup] = []
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var errorMessage: String?

    let restaurantId: UUID

    init(restaurantId: UUID) {
        self.restaurantId = restaurantId
    }

    // MARK: - Fetch

    func fetchMenu() async {
        isLoading = true

        do {
            async let cats = SupabaseService.shared.fetchAllMenuCategories(restaurantId: restaurantId)
            async let menuItems = SupabaseService.shared.fetchAllMenuItems(restaurantId: restaurantId)
            async let mods = SupabaseService.shared.fetchAllModifierGroups(restaurantId: restaurantId)

            categories = try await cats.sorted { $0.sortOrder < $1.sortOrder }
            items = try await menuItems
            modifierGroups = try await mods
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func items(for category: MenuCategory) -> [MenuItem] {
        items.filter { $0.categoryId == category.id }
            .sorted { lhs, rhs in
                if lhs.isSoftDeleted != rhs.isSoftDeleted { return !lhs.isSoftDeleted }
                return lhs.sortOrder < rhs.sortOrder
            }
    }

    // MARK: - Menu Item CRUD

    func toggleAvailability(item: MenuItem) async {
        do {
            try await SupabaseService.shared.toggleMenuItemAvailability(id: item.id, isAvailable: !item.isAvailable)
            items = try await SupabaseService.shared.fetchAllMenuItems(restaurantId: restaurantId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateMenuItem(
        id: UUID,
        name: String,
        description: String?,
        price: Double,
        isAvailable: Bool,
        sortOrder: Int,
        stockCount: Int?
    ) async {
        isSaving = true
        do {
            try await SupabaseService.shared.updateMenuItem(
                id: id,
                name: name,
                description: description,
                price: price,
                isAvailable: isAvailable,
                sortOrder: sortOrder
            )
            try await SupabaseService.shared.updateStock(menuItemId: id, count: stockCount)
            items = try await SupabaseService.shared.fetchAllMenuItems(restaurantId: restaurantId)
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }

    func createItem(
        categoryId: UUID,
        name: String,
        description: String?,
        price: Double,
        imageData: Data?,
        sortOrder: Int
    ) async {
        isSaving = true
        do {
            var imageUrl: String?
            let insert = MenuItemInsert(
                restaurantId: restaurantId,
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

            items = try await SupabaseService.shared.fetchAllMenuItems(restaurantId: restaurantId)
        } catch {
            errorMessage = mapError(error)
        }
        isSaving = false
    }

    func deleteItem(id: UUID) async {
        do {
            try await SupabaseService.shared.deleteMenuItem(id: id)
            items = try await SupabaseService.shared.fetchAllMenuItems(restaurantId: restaurantId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restoreItem(id: UUID) async {
        do {
            try await SupabaseService.shared.restoreMenuItem(id: id)
            items = try await SupabaseService.shared.fetchAllMenuItems(restaurantId: restaurantId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func uploadMenuItemImage(menuItemId: UUID, imageData: Data) async {
        isSaving = true
        do {
            _ = try await SupabaseService.shared.uploadMenuItemImage(
                menuItemId: menuItemId,
                imageData: imageData,
                fileExtension: "jpg"
            )
            items = try await SupabaseService.shared.fetchAllMenuItems(restaurantId: restaurantId)
        } catch {
            errorMessage = mapError(error)
        }
        isSaving = false
    }

    // MARK: - Category CRUD

    func createCategory(name: String, sortOrder: Int) async {
        isSaving = true
        do {
            let insert = MenuCategoryInsert(
                restaurantId: restaurantId,
                name: name,
                sortOrder: sortOrder
            )
            _ = try await SupabaseService.shared.createMenuCategory(insert)
            categories = try await SupabaseService.shared.fetchAllMenuCategories(restaurantId: restaurantId)
                .sorted { $0.sortOrder < $1.sortOrder }
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }

    func updateCategory(id: UUID, name: String?, sortOrder: Int?) async {
        isSaving = true
        do {
            try await SupabaseService.shared.updateMenuCategory(id: id, name: name, sortOrder: sortOrder)
            categories = try await SupabaseService.shared.fetchAllMenuCategories(restaurantId: restaurantId)
                .sorted { $0.sortOrder < $1.sortOrder }
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }

    func deleteCategory(id: UUID) async {
        do {
            try await SupabaseService.shared.deleteMenuCategory(id: id)
            categories = try await SupabaseService.shared.fetchAllMenuCategories(restaurantId: restaurantId)
                .sorted { $0.sortOrder < $1.sortOrder }
        } catch {
            errorMessage = mapError(error)
        }
    }

    func restoreCategory(id: UUID) async {
        do {
            try await SupabaseService.shared.restoreMenuCategory(id: id)
            categories = try await SupabaseService.shared.fetchAllMenuCategories(restaurantId: restaurantId)
                .sorted { $0.sortOrder < $1.sortOrder }
        } catch {
            errorMessage = mapError(error)
        }
    }

    func toggleCategoryAvailability(_ category: MenuCategory) async {
        do {
            try await SupabaseService.shared.toggleMenuCategoryAvailability(id: category.id, isAvailable: !category.isAvailable)
            categories = try await SupabaseService.shared.fetchAllMenuCategories(restaurantId: restaurantId)
                .sorted { $0.sortOrder < $1.sortOrder }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Modifier Group CRUD

    func createModifierGroup(name: String, isRequired: Bool, minSelections: Int, maxSelections: Int, sortOrder: Int) async {
        isSaving = true
        do {
            let insert = ModifierGroupInsert(
                restaurantId: restaurantId,
                name: name,
                isRequired: isRequired,
                minSelections: minSelections,
                maxSelections: maxSelections,
                sortOrder: sortOrder
            )
            _ = try await SupabaseService.shared.createModifierGroup(insert)
            modifierGroups = try await SupabaseService.shared.fetchAllModifierGroups(restaurantId: restaurantId)
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }

    func updateModifierGroup(id: UUID, name: String?, isRequired: Bool?, minSelections: Int?, maxSelections: Int?, sortOrder: Int?) async {
        isSaving = true
        do {
            try await SupabaseService.shared.updateModifierGroup(
                id: id,
                name: name,
                isRequired: isRequired,
                minSelections: minSelections,
                maxSelections: maxSelections,
                sortOrder: sortOrder
            )
            modifierGroups = try await SupabaseService.shared.fetchAllModifierGroups(restaurantId: restaurantId)
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }

    func deleteModifierGroup(id: UUID) async {
        do {
            try await SupabaseService.shared.deleteModifierGroup(id: id)
            modifierGroups = try await SupabaseService.shared.fetchAllModifierGroups(restaurantId: restaurantId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Modifier Option CRUD

    func createModifierOption(groupId: UUID, name: String, priceAdjustment: Double, sortOrder: Int) async {
        isSaving = true
        do {
            let insert = ModifierOptionInsert(
                groupId: groupId,
                name: name,
                priceAdjustment: priceAdjustment,
                sortOrder: sortOrder
            )
            _ = try await SupabaseService.shared.createModifierOption(insert)
            modifierGroups = try await SupabaseService.shared.fetchAllModifierGroups(restaurantId: restaurantId)
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }

    func updateModifierOption(id: UUID, name: String?, priceAdjustment: Double?, isAvailable: Bool?, sortOrder: Int?) async {
        isSaving = true
        do {
            try await SupabaseService.shared.updateModifierOption(
                id: id,
                name: name,
                priceAdjustment: priceAdjustment,
                isAvailable: isAvailable,
                sortOrder: sortOrder
            )
            modifierGroups = try await SupabaseService.shared.fetchAllModifierGroups(restaurantId: restaurantId)
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }

    func deleteModifierOption(id: UUID) async {
        do {
            try await SupabaseService.shared.deleteModifierOption(id: id)
            modifierGroups = try await SupabaseService.shared.fetchAllModifierGroups(restaurantId: restaurantId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Modifier Linking

    func linkModifierToItem(menuItemId: UUID, modifierGroupId: UUID) async {
        do {
            try await SupabaseService.shared.linkModifierGroup(menuItemId: menuItemId, modifierGroupId: modifierGroupId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func unlinkModifierFromItem(menuItemId: UUID, modifierGroupId: UUID) async {
        do {
            try await SupabaseService.shared.unlinkModifierGroup(menuItemId: menuItemId, modifierGroupId: modifierGroupId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Error Mapping

    private func mapError(_ error: Error) -> String {
        let desc = error.localizedDescription
        if desc.contains("categoryNotEmpty") {
            return "Сначала удалите все блюда из категории"
        } else if desc.contains("imageTooLarge") {
            return "Фото слишком большое (макс. 5 МБ)"
        } else if desc.contains("unsupportedImageFormat") {
            return "Поддерживаются только JPG, PNG, WEBP"
        }
        return desc
    }
}
