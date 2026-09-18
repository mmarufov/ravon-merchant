import SwiftUI
import RavonCore

struct MenuView: View {
    @StateObject private var vm: MenuViewModel

    @State private var showCreateCategory = false
    @State private var showCreateItem = false
    @State private var newCategoryName = ""
    @State private var editingCategory: MenuCategory?
    @State private var editCategoryName = ""
    @State private var pendingDeleteItem: MenuItem?
    @State private var pendingDeleteCategory: MenuCategory?

    init(restaurantId: UUID) {
        _vm = StateObject(wrappedValue: MenuViewModel(restaurantId: restaurantId))
    }

    /// True while any sheet covers this screen. The sheets present the error themselves;
    /// the screen must not try to present it at the same time.
    private var isPresentingSheet: Bool {
        showCreateCategory || showCreateItem || editingCategory != nil
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
                            categorySection(category)
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
                        Button { showCreateCategory = true } label: { Image(systemName: "plus") }
                        NavigationLink(destination: ModifierGroupsView(vm: vm)) {
                            Image(systemName: "slider.horizontal.3")
                        }
                    }
                }
            }
            .task { await vm.fetchMenu() }
            .refreshable { await vm.fetchMenu() }
            .sheet(isPresented: $showCreateCategory) { createCategorySheet }
            .sheet(isPresented: $showCreateItem) { MenuItemCreateView(vm: vm) }
            .sheet(item: $editingCategory) { category in editCategorySheet(category) }
            .alert("Удалить блюдо?", isPresented: deleteItemAlertBinding, presenting: pendingDeleteItem) { item in
                Button("Удалить", role: .destructive) {
                    Task { await vm.deleteItem(id: item.id) }
                }
                Button("Отмена", role: .cancel) {}
            } message: { _ in
                Text("История заказов сохранится. У вас будет 30 дней, чтобы восстановить.")
            }
            .alert("Удалить категорию?", isPresented: deleteCategoryAlertBinding, presenting: pendingDeleteCategory) { category in
                Button("Удалить", role: .destructive) {
                    Task { await vm.deleteCategory(id: category.id) }
                }
                Button("Отмена", role: .cancel) {}
            } message: { _ in
                Text("Категория будет скрыта от клиентов. У вас будет 30 дней, чтобы восстановить. Если в категории есть блюда — сначала удалите их.")
            }
            .errorAlert($vm.errorMessage, suppressed: isPresentingSheet)
        }
    }

    // MARK: - Category section

    @ViewBuilder
    private func categorySection(_ category: MenuCategory) -> some View {
        let categoryItems = vm.items(for: category)
        Section {
            if category.isSoftDeleted {
                deletedCategoryRow(category)
            } else {
                if categoryItems.isEmpty {
                    Text("Нет блюд").foregroundStyle(.secondary)
                }
                ForEach(categoryItems) { item in
                    if item.isSoftDeleted {
                        deletedItemRow(item)
                    } else {
                        NavigationLink(value: item.id) { MenuItemRow(item: item) }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    pendingDeleteItem = item
                                } label: { Label("Удалить", systemImage: "trash") }

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
            }
        } header: {
            categoryHeader(category)
        }
    }

    private func categoryHeader(_ category: MenuCategory) -> some View {
        HStack(spacing: 8) {
            Text(category.name)
                .strikethrough(category.isSoftDeleted, color: .secondary)
                .foregroundStyle(category.isSoftDeleted ? .secondary : .primary)
            if category.isSoftDeleted {
                statusPill(text: "Удалено", tint: .red)
            } else if !category.isAvailable {
                statusPill(text: "Скрыто", tint: .orange)
            }
            Spacer()
            if !category.isSoftDeleted {
                Button {
                    Task { await vm.toggleCategoryAvailability(category) }
                } label: {
                    Image(systemName: category.isAvailable ? "eye" : "eye.slash")
                        .font(.caption)
                }
                .help(category.isAvailable ? "Скрыть категорию от клиентов" : "Показать категорию клиентам")

                Button {
                    editingCategory = category
                    editCategoryName = category.name
                } label: { Image(systemName: "pencil").font(.caption) }

                Button(role: .destructive) {
                    pendingDeleteCategory = category
                } label: { Image(systemName: "trash").font(.caption) }
            } else {
                Button {
                    Task { await vm.restoreCategory(id: category.id) }
                } label: {
                    Label("Восстановить", systemImage: "arrow.uturn.backward").font(.caption)
                }
            }
        }
    }

    private func deletedItemRow(_ item: MenuItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .strikethrough(true, color: .secondary)
                    .foregroundStyle(.secondary)
                Text("Удалено — будет очищено через 30 дней")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Восстановить") {
                Task { await vm.restoreItem(id: item.id) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func deletedCategoryRow(_ category: MenuCategory) -> some View {
        Text("Категория удалена — будет очищена через 30 дней")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func statusPill(text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.15))
            .foregroundStyle(tint)
            .clipShape(Capsule())
    }

    // MARK: - Alert bindings

    private var deleteItemAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingDeleteItem != nil },
            set: { if !$0 { pendingDeleteItem = nil } }
        )
    }

    private var deleteCategoryAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingDeleteCategory != nil },
            set: { if !$0 { pendingDeleteCategory = nil } }
        )
    }

    // MARK: - Sheets

    private var createCategorySheet: some View {
        NavigationStack {
            Form {
                TextField("Название категории", text: $newCategoryName)
                RavonPrimaryButton("Создать", isLoading: vm.isSaving) {
                    Task {
                        await vm.createCategory(name: newCategoryName, sortOrder: vm.categories.count)
                        if vm.errorMessage == nil {
                            newCategoryName = ""
                            showCreateCategory = false
                        }
                    }
                }
                .disabled(newCategoryName.isEmpty)
            }
            .errorAlert($vm.errorMessage)
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

    private func editCategorySheet(_ category: MenuCategory) -> some View {
        NavigationStack {
            Form {
                TextField("Название категории", text: $editCategoryName)
                RavonPrimaryButton("Сохранить", isLoading: vm.isSaving) {
                    Task {
                        await vm.updateCategory(id: category.id, name: editCategoryName, sortOrder: nil)
                        if vm.errorMessage == nil { editingCategory = nil }
                    }
                }
                .disabled(editCategoryName.isEmpty)
            }
            .errorAlert($vm.errorMessage)
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
                Text(item.name).font(.body)
                if let desc = item.description, !desc.isEmpty {
                    Text(desc).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(Int(item.price)) сомони")
                    .font(.subheadline.bold()).monospacedDigit()
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
