import SwiftUI
import RavonCore

struct OrderDetailView: View {
    let orderId: UUID
    @ObservedObject var vm: OrdersViewModel

    @State private var showAcceptSheet = false
    @State private var showRejectSheet = false
    @State private var estimatedMinutes = 20
    @State private var rejectReason = ""

    private var order: Order? {
        vm.orders.first { $0.id == orderId }
    }

    var body: some View {
        Group {
            if let order {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        statusSection(order)
                        itemsSection(order)

                        if let address = order.deliveryAddressSnapshot {
                            deliverySection(address)
                        }

                        if let notes = order.notes, !notes.isEmpty {
                            notesSection(notes)
                        }

                        actionsSection(order)
                    }
                    .padding()
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Заказ #\(orderId.uuidString.prefix(6).uppercased())")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAcceptSheet) {
            acceptSheet
        }
        .sheet(isPresented: $showRejectSheet) {
            rejectSheet
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func statusSection(_ order: Order) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Статус")
                .font(.headline)
            Text(order.status.displayName)
                .font(.title3.bold())
                .foregroundStyle(statusColor(for: order.status))
            Text("Создан: \(order.createdAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 16)
    }

    @ViewBuilder
    private func itemsSection(_ order: Order) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Позиции")
                .font(.headline)

            if let items = order.orderItems {
                ForEach(items) { item in
                    HStack {
                        Text(item.itemName)
                        Spacer()
                        Text("x\(item.quantity)")
                            .foregroundStyle(.secondary)
                        Text("\(Int(item.totalPrice)) сум")
                            .monospacedDigit()
                    }

                    if item.id != items.last?.id {
                        Divider()
                    }
                }

                Divider()

                HStack {
                    Text("Доставка")
                    Spacer()
                    Text("\(Int(order.deliveryFee)) сум")
                        .monospacedDigit()
                }
                .foregroundStyle(.secondary)

                HStack {
                    Text("Итого")
                        .fontWeight(.semibold)
                    Spacer()
                    Text("\(Int(order.total)) сум")
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
            }
        }
        .cardStyle(padding: 16)
    }

    @ViewBuilder
    private func deliverySection(_ address: AddressSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Доставка")
                .font(.headline)
            if let street = address.street {
                Text(street)
            }
            if let apt = address.apartment {
                Text("Кв. \(apt)")
                    .foregroundStyle(.secondary)
            }
            if let city = address.city {
                Text(city)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 16)
    }

    @ViewBuilder
    private func notesSection(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Комментарий")
                .font(.headline)
            Text(notes)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 16)
    }

    @ViewBuilder
    private func actionsSection(_ order: Order) -> some View {
        switch order.status {
        case .created:
            HStack(spacing: 12) {
                Button {
                    showRejectSheet = true
                } label: {
                    Text("Отклонить")
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .foregroundStyle(.red)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button {
                    showAcceptSheet = true
                } label: {
                    Text("Принять")
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.ravonRed)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }

        case .accepted:
            RavonPrimaryButton("Начать готовить") {
                Task { await vm.advanceOrder(order.id, currentStatus: .accepted) }
            }

        case .preparing:
            RavonPrimaryButton("Готово") {
                Task { await vm.advanceOrder(order.id, currentStatus: .preparing) }
            }

        default:
            EmptyView()
        }
    }

    // MARK: - Sheets

    private var acceptSheet: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Время приготовления")
                    .font(.headline)

                Stepper("\(estimatedMinutes) мин", value: $estimatedMinutes, in: 5...120, step: 5)
                    .font(.title3)
                    .padding()
                    .cardStyle(padding: 0)

                RavonPrimaryButton("Принять заказ") {
                    Task {
                        await vm.acceptOrder(orderId, estimatedPrepMinutes: estimatedMinutes)
                        showAcceptSheet = false
                    }
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Принять заказ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { showAcceptSheet = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var rejectSheet: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Причина отклонения")
                    .font(.headline)

                TextField("Например: закрыты, нет ингредиентов...", text: $rejectReason, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...6)

                RavonPrimaryButton("Отклонить заказ") {
                    Task {
                        await vm.rejectOrder(orderId, reason: rejectReason)
                        showRejectSheet = false
                        rejectReason = ""
                    }
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Отклонить заказ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { showRejectSheet = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func statusColor(for status: OrderStatus) -> Color {
        switch status {
        case .created: return .orange
        case .accepted: return .blue
        case .preparing: return .purple
        case .ready: return .green
        case .cancelled: return .red
        default: return .gray
        }
    }
}
