import SwiftUI
import RavonCore

struct SettingsView: View {
    @StateObject private var vm: SettingsViewModel
    @State private var showEditSheet = false
    @State private var showPauseAlert = false
    @State private var showCloseAlert = false
    @State private var showCloseConfirmation = false

    init(restaurantId: UUID) {
        _vm = StateObject(wrappedValue: SettingsViewModel(restaurantId: restaurantId))
    }

    var body: some View {
        NavigationStack {
            List {
                if let restaurant = vm.restaurant {
                    // Restaurant status section
                    Section("Статус ресторана") {
                        HStack {
                            Text("Статус")
                            Spacer()
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(statusColor(for: restaurant))
                                    .frame(width: 10, height: 10)
                                Text(statusText(for: restaurant))
                                    .foregroundStyle(statusColor(for: restaurant))
                            }
                        }

                        if restaurant.restaurantStatus == .active {
                            Button("Приостановить ресторан") {
                                showPauseAlert = true
                            }
                            .foregroundStyle(.orange)
                        } else if restaurant.restaurantStatus == .paused {
                            Button("Возобновить ресторан") {
                                Task { await vm.resumeRestaurant() }
                            }
                            .foregroundStyle(.green)
                        }
                    }

                    Section("Ресторан") {
                        Toggle("Принимаем заказы", isOn: Binding(
                            get: { restaurant.isAcceptingOrders },
                            set: { newValue in
                                Task { await vm.toggleAcceptingOrders(newValue) }
                            }
                        ))
                        .tint(Color.ravonRed)
                        .disabled(restaurant.restaurantStatus != .active)

                        LabeledContent("Название", value: restaurant.name)
                        LabeledContent("Кухня", value: restaurant.cuisineType)
                        if let address = restaurant.address {
                            LabeledContent("Адрес", value: address)
                        }
                        LabeledContent("Мин. заказ", value: "\(Int(restaurant.minOrderAmount)) сум")
                        LabeledContent("Стоимость доставки", value: "\(Int(restaurant.deliveryFee)) сум")
                        if let max = restaurant.maxConcurrentOrders {
                            LabeledContent("Макс. одновременных", value: "\(max)")
                        }

                        Button("Редактировать") {
                            showEditSheet = true
                        }
                    }

                    Section("Часы работы") {
                        NavigationLink(destination: RestaurantHoursView(vm: vm)) {
                            if vm.hours.isEmpty {
                                Text("Не настроены")
                                    .foregroundStyle(.secondary)
                            } else {
                                VStack(alignment: .leading, spacing: 2) {
                                    ForEach(vm.hours.sorted(by: { $0.dayOfWeek < $1.dayOfWeek })) { h in
                                        HStack {
                                            Text(h.dayName)
                                                .font(.caption)
                                            Spacer()
                                            Text(h.isClosed ? "Закрыто" : "\(h.openingTime.prefix(5))–\(h.closingTime.prefix(5))")
                                                .font(.caption)
                                                .foregroundStyle(h.isClosed ? .red : .secondary)
                                        }
                                    }
                                }
                            }
                        }
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

                // Danger zone
                if let restaurant = vm.restaurant,
                   restaurant.restaurantStatus == .active || restaurant.restaurantStatus == .paused {
                    Section {
                        Button("Закрыть ресторан навсегда", role: .destructive) {
                            showCloseAlert = true
                        }
                    } header: {
                        Text("Опасная зона")
                    } footer: {
                        Text("Это действие необратимо. Ресторан будет закрыт навсегда.")
                    }
                }

                Section {
                    Button("Выйти", role: .destructive) {
                        Task {
                            await vm.signOut()
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
            .sheet(isPresented: $showEditSheet) {
                if let restaurant = vm.restaurant {
                    RestaurantEditView(restaurant: restaurant, vm: vm)
                }
            }
            .alert("Приостановить ресторан?", isPresented: $showPauseAlert) {
                Button("Приостановить", role: .destructive) {
                    Task { await vm.pauseRestaurant() }
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Ресторан перестанет принимать заказы. Вы сможете возобновить работу в любой момент.")
            }
            .alert("Закрыть ресторан навсегда?", isPresented: $showCloseAlert) {
                Button("Да, закрыть навсегда", role: .destructive) {
                    showCloseConfirmation = true
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Это действие необратимо. Вы уверены?")
            }
            .alert("Подтвердите закрытие", isPresented: $showCloseConfirmation) {
                Button("Закрыть навсегда", role: .destructive) {
                    Task { await vm.closeRestaurant() }
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Ресторан будет закрыт безвозвратно. Это действие нельзя отменить.")
            }
            .alert("Ошибка", isPresented: .init(
                get: { vm.errorMessage != nil },
                set: { if !$0 { vm.errorMessage = nil } }
            )) {
                Button("OK") { vm.errorMessage = nil }
            } message: {
                Text(vm.errorMessage ?? "")
            }
        }
    }

    // MARK: - Helpers

    private func statusColor(for restaurant: Restaurant) -> Color {
        switch restaurant.restaurantStatus {
        case .active: return .green
        case .paused: return .orange
        case .draft: return .gray
        case .closed: return .red
        }
    }

    private func statusText(for restaurant: Restaurant) -> String {
        switch restaurant.restaurantStatus {
        case .active: return "Активен"
        case .paused: return "Приостановлен"
        case .draft: return "Черновик"
        case .closed: return "Закрыт"
        }
    }
}
