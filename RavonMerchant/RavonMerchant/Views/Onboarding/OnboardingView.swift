import SwiftUI
import PhotosUI
import RavonCore

struct OnboardingView: View {
    @StateObject private var vm = OnboardingViewModel()
    let existingRestaurant: Restaurant?
    var onComplete: (Restaurant) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Progress bar
                progressHeader

                // Step content
                TabView(selection: $vm.currentStep) {
                    Step1CreateRestaurant(vm: vm)
                        .tag(1)
                    Step2RestaurantPhoto(vm: vm)
                        .tag(2)
                    Step3Categories(vm: vm)
                        .tag(3)
                    Step4MenuItems(vm: vm)
                        .tag(4)
                    Step5Hours(vm: vm)
                        .tag(5)
                    Step6Preview(vm: vm, onComplete: onComplete)
                        .tag(6)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: vm.currentStep)
            }
            .navigationTitle("Настройка ресторана")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if let existingRestaurant {
                    await vm.resumeOnboarding(for: existingRestaurant)
                }
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

    private var progressHeader: some View {
        VStack(spacing: 8) {
            ProgressView(value: Double(vm.currentStep), total: Double(vm.totalSteps))
                .tint(Color.ravonRed)
            Text("Шаг \(vm.currentStep) из \(vm.totalSteps)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

// MARK: - Step 1: Create Restaurant

private struct Step1CreateRestaurant: View {
    @ObservedObject var vm: OnboardingViewModel

    @State private var name = ""
    @State private var cuisineType = ""
    @State private var address = ""
    @State private var deliveryFee = ""
    @State private var minOrderAmount = ""
    @State private var deliveryTimeMin = ""

    private let cuisineTypes = [
        "Узбекская", "Русская", "Европейская", "Азиатская",
        "Японская", "Итальянская", "Фастфуд", "Кафе", "Другое"
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Создайте ваш ресторан")
                    .font(.title2.bold())

                VStack(spacing: 12) {
                    RavonTextField(icon: "storefront", placeholder: "Название ресторана", text: $name)

                    Picker("Тип кухни", selection: $cuisineType) {
                        Text("Выберите тип кухни").tag("")
                        ForEach(cuisineTypes, id: \.self) { type in
                            Text(type).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    RavonTextField(icon: "mappin", placeholder: "Адрес", text: $address)

                    HStack(spacing: 12) {
                        VStack(alignment: .leading) {
                            Text("Доставка (сум)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            RavonTextField(icon: "banknote", placeholder: "0", text: $deliveryFee, keyboardType: .numberPad)
                        }
                        VStack(alignment: .leading) {
                            Text("Мин. заказ (сум)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            RavonTextField(icon: "cart", placeholder: "0", text: $minOrderAmount, keyboardType: .numberPad)
                        }
                    }

                    VStack(alignment: .leading) {
                        Text("Время доставки (мин)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        RavonTextField(icon: "clock", placeholder: "30", text: $deliveryTimeMin, keyboardType: .numberPad)
                    }
                }

                RavonPrimaryButton("Создать ресторан", isLoading: vm.isLoading) {
                    Task {
                        await vm.createRestaurant(
                            name: name,
                            cuisineType: cuisineType,
                            address: address,
                            deliveryFee: Double(deliveryFee) ?? 0,
                            minOrderAmount: Double(minOrderAmount) ?? 0,
                            deliveryTimeMin: Int(deliveryTimeMin) ?? 30
                        )
                    }
                }
                .disabled(name.isEmpty || cuisineType.isEmpty || address.isEmpty)
            }
            .padding()
        }
    }
}

// MARK: - Step 2: Restaurant Photo

private struct Step2RestaurantPhoto: View {
    @ObservedObject var vm: OnboardingViewModel

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var photoImage: Image?
    @State private var uploaded = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("Фото ресторана")
                    .font(.title2.bold())

                Text("Добавьте фото, чтобы клиенты могли узнать ваш ресторан")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if let photoImage {
                    photoImage
                        .resizable()
                        .scaledToFill()
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray5))
                        .frame(height: 200)
                        .overlay {
                            Image(systemName: "camera")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                        }
                }

                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Text(photoData == nil ? "Выбрать фото" : "Изменить фото")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .onChange(of: selectedPhoto) { _, newValue in
                    Task {
                        if let data = try? await newValue?.loadTransferable(type: Data.self) {
                            photoData = data
                            #if canImport(UIKit)
                            if let uiImage = UIImage(data: data) {
                                photoImage = Image(uiImage: uiImage)
                            }
                            #endif
                        }
                    }
                }

                if let photoData, !uploaded {
                    RavonPrimaryButton("Загрузить фото", isLoading: vm.isLoading) {
                        Task {
                            await vm.uploadRestaurantPhoto(imageData: photoData)
                            uploaded = true
                            vm.currentStep = 3
                        }
                    }
                }

                if uploaded {
                    Label("Фото загружено", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }

                Button("Пропустить") {
                    vm.skipPhoto()
                }
                .foregroundStyle(.secondary)
            }
            .padding()
        }
    }
}

// MARK: - Step 3: Categories

private struct Step3Categories: View {
    @ObservedObject var vm: OnboardingViewModel

    @State private var selectedSuggestions: Set<String> = []
    @State private var customCategoryName = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Категории меню")
                    .font(.title2.bold())

                Text("Выберите подходящие категории или добавьте свои")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                // Suggested categories as chips
                if !vm.suggestedCategories.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(vm.suggestedCategories, id: \.self) { name in
                            Button {
                                if selectedSuggestions.contains(name) {
                                    selectedSuggestions.remove(name)
                                } else {
                                    selectedSuggestions.insert(name)
                                }
                            } label: {
                                Text(name)
                                    .font(.subheadline)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        selectedSuggestions.contains(name)
                                            ? Color.ravonRed.opacity(0.15)
                                            : Color(.systemGray5)
                                    )
                                    .foregroundStyle(
                                        selectedSuggestions.contains(name)
                                            ? Color.ravonRed
                                            : .primary
                                    )
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }

                // Custom category
                HStack {
                    RavonTextField(icon: "plus.circle", placeholder: "Своя категория", text: $customCategoryName)
                    Button("Добавить") {
                        guard !customCategoryName.isEmpty else { return }
                        selectedSuggestions.insert(customCategoryName)
                        customCategoryName = ""
                    }
                    .buttonStyle(.bordered)
                    .disabled(customCategoryName.isEmpty)
                }

                // Already created (swipe to delete)
                if !vm.createdCategories.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Созданные категории:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(vm.createdCategories) { cat in
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text(cat.name)
                                Spacer()
                                Button {
                                    Task { await vm.deleteCategory(id: cat.id) }
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                RavonPrimaryButton("Создать категории", isLoading: vm.isLoading) {
                    Task {
                        await vm.createCategories(names: Array(selectedSuggestions))
                    }
                }
                .disabled(selectedSuggestions.isEmpty && vm.createdCategories.isEmpty)

                if !vm.createdCategories.isEmpty {
                    Button("Далее") {
                        vm.currentStep = 4
                    }
                    .foregroundStyle(Color.ravonRed)
                }
            }
            .padding()
        }
    }
}

// MARK: - FlowLayout helper

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var maxHeight: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxHeight = max(maxHeight, y + rowHeight)
        }

        return (CGSize(width: maxWidth, height: maxHeight), positions)
    }
}

// MARK: - Step 4: Menu Items

private struct Step4MenuItems: View {
    @ObservedObject var vm: OnboardingViewModel

    @State private var selectedCategoryId: UUID?
    @State private var itemName = ""
    @State private var itemPrice = ""
    @State private var itemDescription = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Добавьте блюда")
                    .font(.title2.bold())

                Text("Добавьте хотя бы одно блюдо в меню")
                    .font(.body)
                    .foregroundStyle(.secondary)

                // Category picker
                Picker("Категория", selection: $selectedCategoryId) {
                    Text("Выберите категорию").tag(UUID?.none)
                    ForEach(vm.createdCategories) { cat in
                        Text(cat.name).tag(UUID?.some(cat.id))
                    }
                }
                .pickerStyle(.menu)

                VStack(spacing: 12) {
                    RavonTextField(icon: "fork.knife", placeholder: "Название блюда", text: $itemName)
                    RavonTextField(icon: "text.alignleft", placeholder: "Описание (необязательно)", text: $itemDescription)
                    RavonTextField(icon: "banknote", placeholder: "Цена (сум)", text: $itemPrice, keyboardType: .numberPad)
                }

                RavonPrimaryButton("Добавить блюдо", isLoading: vm.isLoading) {
                    Task {
                        guard let categoryId = selectedCategoryId else { return }
                        await vm.createMenuItem(
                            categoryId: categoryId,
                            name: itemName,
                            price: Double(itemPrice) ?? 0,
                            description: itemDescription.isEmpty ? nil : itemDescription,
                            imageData: nil
                        )
                        if vm.errorMessage == nil {
                            itemName = ""
                            itemPrice = ""
                            itemDescription = ""
                        }
                    }
                }
                .disabled(itemName.isEmpty || itemPrice.isEmpty || selectedCategoryId == nil)

                // Show created items
                if !vm.createdItems.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Добавленные блюда (\(vm.createdItems.count)):")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(vm.createdItems) { item in
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text(item.name)
                                Spacer()
                                Text("\(Int(item.price)) сум")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button("Далее") {
                        vm.currentStep = 5
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.ravonRed)
                }
            }
            .padding()
        }
    }
}

// MARK: - Step 5: Hours

private struct Step5Hours: View {
    @ObservedObject var vm: OnboardingViewModel

    @State private var entries: [DayEntry] = []
    @State private var didLoad = false

    struct DayEntry: Identifiable {
        let dayOfWeek: Int
        var openingTime: Date
        var closingTime: Date
        var isClosed: Bool
        var id: Int { dayOfWeek }

        var dayName: String {
            switch dayOfWeek {
            case 0: return "Воскресенье"
            case 1: return "Понедельник"
            case 2: return "Вторник"
            case 3: return "Среда"
            case 4: return "Четверг"
            case 5: return "Пятница"
            case 6: return "Суббота"
            default: return ""
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Часы работы")
                    .font(.title2.bold())

                Text("Укажите время работы ресторана")
                    .font(.body)
                    .foregroundStyle(.secondary)

                ForEach($entries) { $entry in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(entry.dayName)
                                .font(.headline)
                            Spacer()
                            Toggle("Закрыто", isOn: $entry.isClosed)
                                .labelsHidden()
                            Text(entry.isClosed ? "Закрыто" : "Открыто")
                                .font(.caption)
                                .foregroundStyle(entry.isClosed ? .red : .green)
                        }

                        if !entry.isClosed {
                            HStack {
                                DatePicker("С", selection: $entry.openingTime, displayedComponents: .hourAndMinute)
                                DatePicker("До", selection: $entry.closingTime, displayedComponents: .hourAndMinute)
                            }
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                RavonPrimaryButton("Сохранить и далее", isLoading: vm.isLoading) {
                    Task { await saveAndAdvance() }
                }
                .disabled(entries.allSatisfy { $0.isClosed })
            }
            .padding()
        }
        .onAppear {
            if !didLoad {
                loadDefaults()
                didLoad = true
            }
        }
    }

    private func saveAndAdvance() async {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"

        let hourEntries = entries.map { entry in
            (
                dayOfWeek: entry.dayOfWeek,
                openingTime: formatter.string(from: entry.openingTime),
                closingTime: formatter.string(from: entry.closingTime),
                isClosed: entry.isClosed
            )
        }
        await vm.saveHours(hourEntries)
    }

    private func loadDefaults() {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let defaultOpen = formatter.date(from: "09:00:00") ?? Date()
        let defaultClose = formatter.date(from: "22:00:00") ?? Date()

        let dayOrder = [1, 2, 3, 4, 5, 6, 0]
        entries = dayOrder.map { day in
            DayEntry(
                dayOfWeek: day,
                openingTime: defaultOpen,
                closingTime: defaultClose,
                isClosed: false
            )
        }
    }
}

// MARK: - Step 6: Preview & Go Live

private struct Step6Preview: View {
    @ObservedObject var vm: OnboardingViewModel
    var onComplete: (Restaurant) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("Предпросмотр")
                    .font(.title2.bold())

                // Progress bar
                if let progress = vm.progress {
                    VStack(spacing: 8) {
                        ProgressView(value: progress.completionPercentage)
                            .tint(progress.isReadyToGoLive ? .green : Color.ravonRed)
                        Text("Готовность: \(Int(progress.completionPercentage * 100))%")
                            .font(.subheadline)
                    }

                    // Checklist from OnboardingProgress fields
                    VStack(alignment: .leading, spacing: 8) {
                        checklistItem("Ресторан создан", done: progress.hasRestaurant)
                        checklistItem("Название заполнено", done: progress.hasName)
                        checklistItem("Адрес указан", done: progress.hasAddress)
                        checklistItem("Категории меню", done: progress.hasAtLeastOneCategory)
                        checklistItem("Блюда добавлены", done: progress.hasAtLeastOneMenuItem)
                        checklistItem("Часы работы", done: progress.hasHoursConfigured)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Restaurant preview
                if let preview = vm.previewData {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Как увидят клиенты:")
                            .font(.headline)

                        // Restaurant card
                        VStack(alignment: .leading, spacing: 8) {
                            if let imageUrl = preview.restaurant.imageUrl,
                               let url = URL(string: imageUrl) {
                                AsyncImage(url: url) { phase in
                                    if case .success(let image) = phase {
                                        image
                                            .resizable()
                                            .scaledToFill()
                                            .frame(height: 140)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                }
                            }

                            Text(preview.restaurant.name)
                                .font(.title3.bold())
                            Text(preview.restaurant.cuisineType)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            // Menu preview
                            ForEach(preview.categories.sorted(by: { $0.sortOrder < $1.sortOrder })) { category in
                                let categoryItems = preview.items.filter { $0.categoryId == category.id }
                                if !categoryItems.isEmpty {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(category.name)
                                            .font(.subheadline.bold())
                                            .padding(.top, 4)
                                        ForEach(categoryItems.sorted(by: { $0.sortOrder < $1.sortOrder })) { item in
                                            HStack {
                                                Text(item.name)
                                                    .font(.caption)
                                                Spacer()
                                                Text("\(Int(item.price)) сум")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .monospacedDigit()
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                RavonPrimaryButton("Открыть ресторан", isLoading: vm.isLoading) {
                    Task {
                        await vm.activateRestaurant()
                        if let restaurant = vm.restaurant,
                           restaurant.restaurantStatus == .active {
                            onComplete(restaurant)
                        }
                    }
                }
                .disabled(!(vm.progress?.isReadyToGoLive ?? false))

                if !(vm.progress?.isReadyToGoLive ?? false) {
                    Text("Заполните все обязательные данные для открытия")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding()
        }
        .task {
            await vm.refreshProgress()
            await vm.fetchPreview()
        }
    }

    private func checklistItem(_ text: String, done: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? .green : .secondary)
            Text(text)
                .font(.body)
        }
    }
}
