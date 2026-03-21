import SwiftUI
import RavonCore

struct SettingsView: View {
    @StateObject private var vm: SettingsViewModel
    @AppStorage("selectedRestaurantId") private var selectedRestaurantId: String?

    init(restaurantId: UUID) {
        _vm = StateObject(wrappedValue: SettingsViewModel(restaurantId: restaurantId))
    }

    var body: some View {
        NavigationStack {
            List {
                if let restaurant = vm.restaurant {
                    Section("Ресторан") {
                        LabeledContent("Название", value: restaurant.name)
                        LabeledContent("Кухня", value: restaurant.cuisineType)
                        if let address = restaurant.address {
                            LabeledContent("Адрес", value: address)
                        }
                        LabeledContent("Статус") {
                            Text(restaurant.isActive ? "Активен" : "Неактивен")
                                .foregroundStyle(restaurant.isActive ? .green : .red)
                        }
                        LabeledContent("Мин. заказ", value: "\(Int(restaurant.minOrderAmount)) сум")
                        LabeledContent("Стоимость доставки", value: "\(Int(restaurant.deliveryFee)) сум")
                    }
                }

                if let profile = vm.profile {
                    Section("Профиль") {
                        LabeledContent("Имя", value: profile.fullName)
                        if let phone = profile.phone {
                            LabeledContent("Телефон", value: phone)
                        }
                        LabeledContent("Роль", value: profile.role.displayName)
                    }
                }

                Section {
                    Button("Сменить ресторан") {
                        selectedRestaurantId = nil
                    }
                }

                Section {
                    Button("Выйти", role: .destructive) {
                        Task {
                            await vm.signOut()
                            selectedRestaurantId = nil
                        }
                    }
                }
            }
            .navigationTitle("Настройки")
            .task {
                await vm.fetchData()
            }
            .refreshable {
                await vm.fetchData()
            }
        }
    }
}
