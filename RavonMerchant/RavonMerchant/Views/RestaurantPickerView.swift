import SwiftUI
import RavonCore

struct RestaurantPickerView: View {
    let onSelect: (UUID) -> Void

    @State private var restaurants: [Restaurant] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Загрузка...")
                } else if restaurants.isEmpty {
                    ContentUnavailableView(
                        "Нет ресторанов",
                        systemImage: "storefront",
                        description: Text("Рестораны не найдены")
                    )
                } else {
                    List(restaurants) { restaurant in
                        Button {
                            onSelect(restaurant.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(restaurant.name)
                                    .font(.headline)
                                Text(restaurant.cuisineType)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                if let address = restaurant.address {
                                    Text(address)
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .tint(.primary)
                    }
                }
            }
            .navigationTitle("Выберите ресторан")
            .task {
                do {
                    restaurants = try await SupabaseService.shared.fetchRestaurants()
                } catch {
                    // Will show empty state
                }
                isLoading = false
            }
        }
    }
}
