import SwiftUI
import RavonCore

struct MenuView: View {
    @StateObject private var vm: MenuViewModel

    init(restaurantId: UUID) {
        _vm = StateObject(wrappedValue: MenuViewModel(restaurantId: restaurantId))
    }

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading {
                    ProgressView()
                } else if vm.categories.isEmpty {
                    ContentUnavailableView(
                        "Меню пусто",
                        systemImage: "menucard",
                        description: Text("Добавьте категории и блюда")
                    )
                } else {
                    List {
                        ForEach(vm.categories) { category in
                            Section(category.name) {
                                let categoryItems = vm.items(for: category)
                                if categoryItems.isEmpty {
                                    Text("Нет блюд")
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(categoryItems) { item in
                                        MenuItemRow(item: item)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Меню")
            .task {
                await vm.fetchMenu()
            }
            .refreshable {
                await vm.fetchMenu()
            }
        }
    }
}

// MARK: - Menu Item Row

struct MenuItemRow: View {
    let item: MenuItem

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.body)
                if let desc = item.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(Int(item.price)) сум")
                    .font(.subheadline.bold())
                    .monospacedDigit()
                Text(item.isAvailable ? "В наличии" : "Нет в наличии")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(item.isAvailable ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                    .foregroundStyle(item.isAvailable ? .green : .red)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 2)
    }
}
