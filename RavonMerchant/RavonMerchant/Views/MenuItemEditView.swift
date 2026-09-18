import SwiftUI
import PhotosUI
import RavonCore

struct MenuItemEditView: View {
    let item: MenuItem
    @ObservedObject var vm: MenuViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var description: String
    @State private var price: String
    @State private var isAvailable: Bool
    @State private var sortOrder: String
    @State private var stockCount: String
    @State private var isUnlimitedStock: Bool

    // Image upload
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isUploadingPhoto = false

    init(item: MenuItem, vm: MenuViewModel) {
        self.item = item
        self.vm = vm
        _name = State(initialValue: item.name)
        _description = State(initialValue: item.description ?? "")
        _price = State(initialValue: String(Int(item.price)))
        _isAvailable = State(initialValue: item.isAvailable)
        _sortOrder = State(initialValue: String(item.sortOrder))
        _stockCount = State(initialValue: item.stockCount.map { String($0) } ?? "")
        _isUnlimitedStock = State(initialValue: item.stockCount == nil)
    }

    var body: some View {
        Form {
            // Photo section
            Section("Фото") {
                if let imageUrl = item.imageUrl, !imageUrl.isEmpty {
                    AsyncImage(url: URL(string: imageUrl)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(height: 160)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        case .failure:
                            photoPlaceholder
                        case .empty:
                            ProgressView()
                                .frame(height: 160)
                        @unknown default:
                            photoPlaceholder
                        }
                    }
                } else {
                    photoPlaceholder
                }

                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label(
                        item.imageUrl != nil ? "Изменить фото" : "Добавить фото",
                        systemImage: "photo"
                    )
                }
                .onChange(of: selectedPhoto) { _, newValue in
                    Task {
                        if let data = try? await newValue?.loadTransferable(type: Data.self) {
                            isUploadingPhoto = true
                            await vm.uploadMenuItemImage(menuItemId: item.id, imageData: data)
                            isUploadingPhoto = false
                        }
                    }
                }

                if isUploadingPhoto {
                    HStack {
                        ProgressView()
                        Text("Загрузка фото...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Основное") {
                TextField("Название блюда", text: $name)
                TextField("Описание", text: $description, axis: .vertical)
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

            Section("Доступность") {
                Toggle("В наличии", isOn: $isAvailable)

                Toggle("Безлимитный остаток", isOn: $isUnlimitedStock)

                if !isUnlimitedStock {
                    HStack {
                        Text("Остаток")
                        Spacer()
                        TextField("0", text: $stockCount)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                }
            }

            Section {
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
                RavonPrimaryButton("Сохранить", isLoading: vm.isSaving) {
                    Task {
                        await vm.updateMenuItem(
                            id: item.id,
                            name: name,
                            description: description.isEmpty ? nil : description,
                            price: Double(price) ?? item.price,
                            isAvailable: isAvailable,
                            sortOrder: Int(sortOrder) ?? item.sortOrder,
                            stockCount: isUnlimitedStock ? nil : Int(stockCount)
                        )
                        // Leaving the screen on failure used to hide the error entirely:
                        // this view had no alert of its own, and the pushed screen popped
                        // before the one behind it could show anything.
                        if vm.errorMessage == nil {
                            dismiss()
                        }
                    }
                }
                .disabled(name.isEmpty)
            }
        }
        .navigationTitle("Редактировать блюдо")
        .navigationBarTitleDisplayMode(.inline)
        // No alert of its own: this screen is *pushed*, not presented, so `MenuView`'s
        // alert shows over it. A second `.errorAlert` on the same message would be two
        // presentations racing for one condition.
    }

    private var photoPlaceholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color(.systemGray5))
            .frame(height: 120)
            .overlay {
                Image(systemName: "photo")
                    .font(.title)
                    .foregroundStyle(.secondary)
            }
    }
}
