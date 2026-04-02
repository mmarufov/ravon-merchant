import SwiftUI
import PhotosUI
import RavonCore

struct RestaurantEditView: View {
    let restaurant: Restaurant
    @ObservedObject var vm: SettingsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var description: String
    @State private var address: String
    @State private var cuisineType: String
    @State private var minOrderAmount: String
    @State private var deliveryFee: String
    @State private var deliveryTimeMin: String
    @State private var maxConcurrentOrders: String

    // Image upload
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isUploadingPhoto = false

    init(restaurant: Restaurant, vm: SettingsViewModel) {
        self.restaurant = restaurant
        self.vm = vm
        _name = State(initialValue: restaurant.name)
        _description = State(initialValue: restaurant.description ?? "")
        _address = State(initialValue: restaurant.address ?? "")
        _cuisineType = State(initialValue: restaurant.cuisineType)
        _minOrderAmount = State(initialValue: String(Int(restaurant.minOrderAmount)))
        _deliveryFee = State(initialValue: String(Int(restaurant.deliveryFee)))
        _deliveryTimeMin = State(initialValue: String(restaurant.deliveryTimeMin))
        _maxConcurrentOrders = State(initialValue: restaurant.maxConcurrentOrders.map { String($0) } ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                // Photo section
                Section("Фото ресторана") {
                    if let imageUrl = restaurant.imageUrl, !imageUrl.isEmpty {
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
                            restaurant.imageUrl != nil ? "Изменить фото" : "Добавить фото",
                            systemImage: "photo"
                        )
                    }
                    .onChange(of: selectedPhoto) { _, newValue in
                        Task {
                            if let data = try? await newValue?.loadTransferable(type: Data.self) {
                                isUploadingPhoto = true
                                await vm.uploadRestaurantImage(imageData: data)
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
                    TextField("Название", text: $name)
                    TextField("Описание", text: $description, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("Адрес", text: $address)
                    TextField("Тип кухни", text: $cuisineType)
                }

                Section("Условия") {
                    HStack {
                        Text("Мин. заказ (сум)")
                        Spacer()
                        TextField("0", text: $minOrderAmount)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                    HStack {
                        Text("Доставка (сум)")
                        Spacer()
                        TextField("0", text: $deliveryFee)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                    HStack {
                        Text("Время доставки (мин)")
                        Spacer()
                        TextField("0", text: $deliveryTimeMin)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                    HStack {
                        Text("Макс. одновременных")
                        Spacer()
                        TextField("—", text: $maxConcurrentOrders)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                }
            }
            .navigationTitle("Редактировать")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        Task {
                            await vm.updateRestaurant(
                                name: name,
                                description: description.isEmpty ? nil : description,
                                address: address.isEmpty ? nil : address,
                                cuisineType: cuisineType,
                                deliveryFee: Double(deliveryFee),
                                minOrderAmount: Double(minOrderAmount),
                                deliveryTimeMin: Int(deliveryTimeMin),
                                maxConcurrentOrders: Int(maxConcurrentOrders)
                            )
                            dismiss()
                        }
                    }
                    .disabled(name.isEmpty || vm.isSaving)
                }
            }
        }
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
