import SwiftUI
import PhotosUI
import RavonCore

struct MenuItemCreateView: View {
    @ObservedObject var vm: MenuViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedCategoryId: UUID?
    @State private var name = ""
    @State private var description = ""
    @State private var price = ""
    @State private var isAvailable = true
    @State private var sortOrder = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var photoImage: Image?

    var body: some View {
        NavigationStack {
            Form {
                Section("Категория") {
                    Picker("Категория", selection: $selectedCategoryId) {
                        Text("Выберите категорию").tag(UUID?.none)
                        ForEach(vm.categories) { category in
                            Text(category.name).tag(UUID?.some(category.id))
                        }
                    }
                }

                Section("Фото") {
                    if let photoImage {
                        photoImage
                            .resizable()
                            .scaledToFill()
                            .frame(height: 160)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label(photoData == nil ? "Добавить фото" : "Изменить фото", systemImage: "photo")
                    }
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
                }

                Section("Основное") {
                    TextField("Название блюда", text: $name)
                    TextField("Описание (необязательно)", text: $description, axis: .vertical)
                        .lineLimit(2...4)
                    HStack {
                        Text("Цена (сомони)")
                        Spacer()
                        TextField("0", text: $price)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                }

                Section("Настройки") {
                    Toggle("В наличии", isOn: $isAvailable)
                    HStack {
                        Text("Порядок сортировки")
                        Spacer()
                        TextField("0", text: $sortOrder)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                }

                Section {
                    RavonPrimaryButton("Создать", isLoading: vm.isSaving) {
                        Task { await createItem() }
                    }
                    .disabled(name.isEmpty || price.isEmpty || selectedCategoryId == nil)
                }
            }
            .navigationTitle("Новое блюдо")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
            .errorAlert($vm.errorMessage)
        }
    }

    private func createItem() async {
        guard let categoryId = selectedCategoryId else { return }
        await vm.createItem(
            categoryId: categoryId,
            name: name,
            description: description.isEmpty ? nil : description,
            price: Double(price) ?? 0,
            imageData: photoData,
            sortOrder: Int(sortOrder) ?? 0
        )
        if vm.errorMessage == nil {
            dismiss()
        }
    }
}
