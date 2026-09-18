import SwiftUI
import RavonCore

struct ModifierGroupsView: View {
    @ObservedObject var vm: MenuViewModel

    @State private var showCreateGroup = false
    @State private var showCreateOption: ModifierGroup?
    @State private var editingGroup: ModifierGroup?
    @State private var editingOption: ModifierOption?
    @State private var linkingGroup: ModifierGroup?

    // Create group form
    @State private var newGroupName = ""
    @State private var newGroupIsRequired = false
    @State private var newGroupMin = 0
    @State private var newGroupMax = 1

    // Create option form
    @State private var newOptionName = ""
    @State private var newOptionPrice = ""

    // Edit group form
    @State private var editGroupName = ""
    @State private var editGroupIsRequired = false
    @State private var editGroupMin = 0
    @State private var editGroupMax = 1

    // Edit option form
    @State private var editOptionName = ""
    @State private var editOptionPrice = ""
    @State private var editOptionAvailable = true

    // Link to item
    @State private var selectedItemId: UUID?

    var body: some View {
        Group {
            if vm.modifierGroups.isEmpty {
                ContentUnavailableView(
                    "Нет модификаторов",
                    systemImage: "slider.horizontal.3",
                    description: Text("Добавьте модификаторы для блюд")
                )
            } else {
                List {
                    ForEach(vm.modifierGroups.sorted(by: { $0.sortOrder < $1.sortOrder })) { group in
                        Section {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(group.name)
                                        .font(.headline)
                                    Spacer()
                                    Text(group.isRequired ? "Обязательно" : "Опционально")
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(group.isRequired ? Color.ravonRed.opacity(0.1) : Color.green.opacity(0.1))
                                        .foregroundStyle(group.isRequired ? Color.ravonRed : .green)
                                        .clipShape(Capsule())
                                }

                                if group.minSelections > 0 || group.maxSelections > 1 {
                                    Text("Выбор: \(group.minSelections)–\(group.maxSelections)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                HStack(spacing: 12) {
                                    Button {
                                        editingGroup = group
                                        editGroupName = group.name
                                        editGroupIsRequired = group.isRequired
                                        editGroupMin = group.minSelections
                                        editGroupMax = group.maxSelections
                                    } label: {
                                        Label("Изменить", systemImage: "pencil")
                                            .font(.caption)
                                    }

                                    Button {
                                        linkingGroup = group
                                    } label: {
                                        Label("Привязать к блюду", systemImage: "link")
                                            .font(.caption)
                                    }
                                }
                            }

                            if let options = group.options, !options.isEmpty {
                                ForEach(options.sorted(by: { $0.sortOrder < $1.sortOrder })) { option in
                                    HStack {
                                        Circle()
                                            .fill(option.isAvailable ? .green : .red)
                                            .frame(width: 8, height: 8)
                                        Text(option.name)
                                        Spacer()
                                        if option.priceAdjustment != 0 {
                                            Text("+\(Int(option.priceAdjustment)) сомони")
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                                .monospacedDigit()
                                        }
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        editingOption = option
                                        editOptionName = option.name
                                        editOptionPrice = String(Int(option.priceAdjustment))
                                        editOptionAvailable = option.isAvailable
                                    }
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            Task { await vm.deleteModifierOption(id: option.id) }
                                        } label: {
                                            Label("Удалить", systemImage: "trash")
                                        }
                                    }
                                }
                            }

                            Button {
                                showCreateOption = group
                                newOptionName = ""
                                newOptionPrice = ""
                            } label: {
                                Label("Добавить опцию", systemImage: "plus")
                                    .foregroundStyle(Color.ravonRed)
                                    .font(.subheadline)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task { await vm.deleteModifierGroup(id: group.id) }
                            } label: {
                                Label("Удалить", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Модификаторы")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showCreateGroup = true
                    newGroupName = ""
                    newGroupIsRequired = false
                    newGroupMin = 0
                    newGroupMax = 1
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showCreateGroup) {
            createGroupSheet
        }
        .sheet(item: $showCreateOption) { group in
            createOptionSheet(group)
        }
        .sheet(item: $editingGroup) { group in
            editGroupSheet(group)
        }
        .sheet(item: $editingOption) { option in
            editOptionSheet(option)
        }
        .sheet(item: $linkingGroup) { group in
            linkItemSheet(group)
        }
        // No screen-level alert here: this view is pushed inside `MenuView`'s stack and
        // `MenuView` already presents `vm.errorMessage`. The sheets below need their own,
        // because an alert cannot be presented from a view a sheet is covering.
    }

    // MARK: - Create Group Sheet

    private var createGroupSheet: some View {
        NavigationStack {
            Form {
                TextField("Название группы", text: $newGroupName)
                Toggle("Обязательный выбор", isOn: $newGroupIsRequired)
                Stepper("Мин. выбор: \(newGroupMin)", value: $newGroupMin, in: 0...10)
                Stepper("Макс. выбор: \(newGroupMax)", value: $newGroupMax, in: 1...10)

                RavonPrimaryButton("Создать", isLoading: vm.isSaving) {
                    Task {
                        await vm.createModifierGroup(
                            name: newGroupName,
                            isRequired: newGroupIsRequired,
                            minSelections: newGroupMin,
                            maxSelections: newGroupMax,
                            sortOrder: vm.modifierGroups.count
                        )
                        if vm.errorMessage == nil {
                            showCreateGroup = false
                        }
                    }
                }
                .disabled(newGroupName.isEmpty)
            }
            .errorAlert($vm.errorMessage)
            .navigationTitle("Новый модификатор")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { showCreateGroup = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Create Option Sheet

    private func createOptionSheet(_ group: ModifierGroup) -> some View {
        NavigationStack {
            Form {
                TextField("Название опции", text: $newOptionName)
                HStack {
                    Text("Доплата (сомони)")
                    Spacer()
                    TextField("0", text: $newOptionPrice)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }

                RavonPrimaryButton("Создать", isLoading: vm.isSaving) {
                    Task {
                        let optionsCount = group.options?.count ?? 0
                        await vm.createModifierOption(
                            groupId: group.id,
                            name: newOptionName,
                            priceAdjustment: Double(newOptionPrice) ?? 0,
                            sortOrder: optionsCount
                        )
                        if vm.errorMessage == nil {
                            showCreateOption = nil
                        }
                    }
                }
                .disabled(newOptionName.isEmpty)
            }
            .errorAlert($vm.errorMessage)
            .navigationTitle("Новая опция")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { showCreateOption = nil }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Edit Group Sheet

    private func editGroupSheet(_ group: ModifierGroup) -> some View {
        NavigationStack {
            Form {
                TextField("Название группы", text: $editGroupName)
                Toggle("Обязательный выбор", isOn: $editGroupIsRequired)
                Stepper("Мин. выбор: \(editGroupMin)", value: $editGroupMin, in: 0...10)
                Stepper("Макс. выбор: \(editGroupMax)", value: $editGroupMax, in: 1...10)

                RavonPrimaryButton("Сохранить", isLoading: vm.isSaving) {
                    Task {
                        await vm.updateModifierGroup(
                            id: group.id,
                            name: editGroupName,
                            isRequired: editGroupIsRequired,
                            minSelections: editGroupMin,
                            maxSelections: editGroupMax,
                            sortOrder: nil
                        )
                        if vm.errorMessage == nil {
                            editingGroup = nil
                        }
                    }
                }
            }
            .errorAlert($vm.errorMessage)
            .navigationTitle("Редактировать")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { editingGroup = nil }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Edit Option Sheet

    private func editOptionSheet(_ option: ModifierOption) -> some View {
        NavigationStack {
            Form {
                TextField("Название", text: $editOptionName)
                HStack {
                    Text("Доплата (сомони)")
                    Spacer()
                    TextField("0", text: $editOptionPrice)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }
                Toggle("Доступно", isOn: $editOptionAvailable)

                RavonPrimaryButton("Сохранить", isLoading: vm.isSaving) {
                    Task {
                        await vm.updateModifierOption(
                            id: option.id,
                            name: editOptionName,
                            priceAdjustment: Double(editOptionPrice),
                            isAvailable: editOptionAvailable,
                            sortOrder: nil
                        )
                        if vm.errorMessage == nil {
                            editingOption = nil
                        }
                    }
                }
            }
            .errorAlert($vm.errorMessage)
            .navigationTitle("Редактировать опцию")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { editingOption = nil }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Link to Item Sheet

    private func linkItemSheet(_ group: ModifierGroup) -> some View {
        NavigationStack {
            List {
                ForEach(vm.items) { item in
                    Button {
                        Task {
                            await vm.linkModifierToItem(menuItemId: item.id, modifierGroupId: group.id)
                            if vm.errorMessage == nil { linkingGroup = nil }
                        }
                    } label: {
                        HStack {
                            Text(item.name)
                            Spacer()
                            Text("\(Int(item.price)) сомони")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(.primary)
                }
            }
            .errorAlert($vm.errorMessage)
            .navigationTitle("Привязать к блюду")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { linkingGroup = nil }
                }
            }
        }
    }
}
