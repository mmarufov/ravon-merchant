import SwiftUI
import RavonCore

struct MenuView: View {
    @StateObject private var vm: MenuViewModel

    @State private var showCreateCategory = false
    @State private var showCreateItem = false
    @State private var newCategoryName = ""
    @State private var editingCategory: MenuCategory?
    @State private var editCategoryName = ""

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
                            Section {
                                let categoryItems = vm.items(for: category)
                                if categoryItems.isEmpty {
                                    Text("Нет блюд")
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(categoryItems) { item in
                                        NavigationLink(value: item.id) {
                                            MenuItemRow(item: item)
                                        }
                                        .swipeActions(edge: .trailing) {
                                            Button(role: .destructive) {
                                                Task { await vm.deleteItem(id: item.id) }
                                            } label: {
                                                Label("Удалить", systemImage: "trash")
                                            }

                                            Button {
                                                Task { await vm.toggleAvailability(item: item) }
                                            } label: {
                                                Label(
                                                    item.isAvailable ? "Убрать" : "Вернуть",
                                                    systemImage: item.isAvailable ? "eye.slash" : "eye"
                                                )
                                            }
                                            .tint(item.isAvailable ? .orange : .green)
                                        }
                                    }
                                }

                                Button {
                                    showCreateItem = true
                                } label: {
                                    Label("Добавить блюдо", systemImage: "plus")
                                        .foregroundStyle(Color.ravonRed)
                                }
                            } header: {
                                HStack {
                                    Text(category.name)
                                    Spacer()
                                    Button {
                                        editingCategory = category
                                        editCategoryName = category.name
                                    } label: {
                                        Image(systemName: "pencil")
                                            .font(.caption)
                                    }
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    Task { await vm.deleteCategory(id: category.id) }
                                } label: {
                                    Label("Удалить", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Меню")
            .navigationDestination(for: UUID.self) { itemId in
                if let item = vm.items.first(where: { $0.id == itemId }) {
                    MenuItemEditView(item: item, vm: vm)
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 12) {
                        Button {
                            showCreateCategory = true
                        } label: {
                            Image(systemName: "plus")
                        }

                        NavigationLink(destination: ModifierGroupsView(vm: vm)) {
                            Image(systemName: "slider.horizontal.3")
                        }
                    }
                }
            }
            .task {
                await vm.fetchMenu()
            }
            .refreshable {
                await vm.fetchMenu()
            }
            .sheet(isPresented: $showCreateCategory) {
                createCategorySheet
            }
            .sheet(isPresented: $showCreateItem) {
                MenuItemCreateView(vm: vm)
            }
            .sheet(item: $editingCategory) { category in
                editCategorySheet(category)
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

    // MARK: - Create Category Sheet

    private var createCategorySheet: some View {
        NavigationStack {
            Form {
                TextField("Название категории", text: $newCategoryName)

                RavonPrimaryButton("Создать", isLoading: vm.isSaving) {
                    Task {
                        await vm.createCategory(
                            name: newCategoryName,
                            sortOrder: vm.categories.count
                        )
                        if vm.errorMessage == nil {
                            newCategoryName = ""
                            showCreateCategory = false
                        }
                    }
                }
                .disabled(newCategoryName.isEmpty)
            }
            .navigationTitle("Новая категория")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        newCategoryName = ""
                        showCreateCategory = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Edit Category Sheet

    private func editCategorySheet(_ category: MenuCategory) -> some View {
        NavigationStack {
            Form {
                TextField("Название категории", text: $editCategoryName)

                RavonPrimaryButton("Сохранить", isLoading: vm.isSaving) {
                    Task {
                        await vm.updateCategory(id: category.id, name: editCategoryName, sortOrder: nil)
                        if vm.errorMessage == nil {
                            editingCategory = nil
                        }
                    }
                }
                .disabled(editCategoryName.isEmpty)
            }
            .navigationTitle("Редактировать категорию")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { editingCategory = nil }
                }
            }
        }
        .presentationDetents([.medium])
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
                if let stock = item.stockCount {
                    Text("Остаток: \(stock)")
                        .font(.caption2)
                        .foregroundStyle(stock == 0 ? .red : .secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
