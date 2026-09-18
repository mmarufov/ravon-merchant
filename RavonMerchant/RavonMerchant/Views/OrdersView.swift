import SwiftUI
import RavonCore

struct OrdersView: View {
    @StateObject private var vm: OrdersViewModel
    @State private var selectedBucket: MerchantQueueBucket = .new

    init(restaurantId: UUID) {
        _vm = StateObject(wrappedValue: OrdersViewModel(restaurantId: restaurantId))
    }

    private var currentOrders: [Order] {
        vm.orders(in: selectedBucket)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $selectedBucket) {
                    ForEach(MerchantQueueBucket.allCases, id: \.self) { bucket in
                        Text("\(bucket.title) (\(vm.orders(in: bucket).count))").tag(bucket)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                if vm.isLoading {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if currentOrders.isEmpty {
                    Spacer()
                    ContentUnavailableView(
                        selectedBucket == .scheduled ? "Нет запланированных" : "Нет заказов",
                        systemImage: selectedBucket == .scheduled ? "calendar" : "tray",
                        description: Text(selectedBucket.emptyMessage)
                    )
                    Spacer()
                } else {
                    List(currentOrders) { order in
                        if selectedBucket == .scheduled {
                            ScheduledOrderRow(order: order)
                                .contentShape(Rectangle())
                        } else {
                            NavigationLink(value: order.id) {
                                OrderRowView(order: order)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Заказы")
            .navigationDestination(for: UUID.self) { orderId in
                OrderDetailView(orderId: orderId, vm: vm)
            }
            .task {
                await vm.fetchOrders()
                await vm.startListening()
            }
            .onDisappear {
                vm.stopListening()
            }
            .refreshable {
                await vm.fetchOrders()
            }
            // Queue-level failures only. Action failures render inline in `OrderDetailView`,
            // which is where the merchant is standing when they happen.
            .errorAlert($vm.listError)
        }
    }
}

// MARK: - Order Row

struct OrderRowView: View {
    let order: Order

    private var isAutoCancelledForRestaurantTooLong: Bool {
        order.status == .cancelledBySystem
            && order.cancellationReasonCode == CancellationReason.restaurantTooLongWait.rawValue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isAutoCancelledForRestaurantTooLong {
                autoCancelBanner
            }

            if order.status == .cancelledByCourier {
                cancelledByCourierHeader
            } else {
                HStack {
                    Text("Заказ #\(order.id.uuidString.prefix(6).uppercased())")
                        .font(.headline)
                    Spacer()
                    Text("\(Int(order.total)) сомони")
                        .font(.headline)
                        .foregroundStyle(Color.ravonRed)
                }
            }

            HStack {
                Label(order.status.displayName, systemImage: statusIcon)
                    .font(.caption)
                    .foregroundStyle(statusColor)
                Spacer()
                Text(order.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if order.merchantShowsPickupCode, let code = order.pickupVerificationCode {
                // Gated on the merchant's `showPickupCode` obligation rather than on a
                // hand-written status list. The old list stopped at `.ready`, so the code
                // disappeared the instant a courier claimed the order — the one moment it
                // is actually needed.
                Text("\(order.isInMerchantHandoff ? "Курьер за заказом" : "Готов к выдаче") — Код для курьера: \(code)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.ravonRed)
            }

            if order.status == .courierArrivedRestaurant {
                Text("Курьер у ресторана — назовите код")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }

            if order.restaurantDelayMin > 0 {
                Text("🕒 Курьер сообщил: задержка +\(order.restaurantDelayMin) мин (всего \(order.restaurantDelayMin)/30)")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if order.reassignCount > 0 && !order.status.isTerminal {
                Text("↻ Поиск нового курьера (попытка \(order.reassignCount)/3)")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }

            if let items = order.orderItems, !items.isEmpty {
                Text(items.map { "\($0.itemName) x\($0.quantity)" }.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    private var autoCancelBanner: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("⚠️ Заказ автоматически отменён")
                .font(.caption.weight(.bold))
                .foregroundStyle(.red)
            Text("Ресторан превысил время ожидания (30 мин). Курьер получил 50% оплаты.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.red.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var cancelledByCourierHeader: some View {
        let reasonText = CancellationReason(rawValue: order.cancellationReasonCode ?? "")?
            .localizedDisplayName ?? "Без причины"
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("[CANCELLED] Заказ #\(order.id.uuidString.prefix(6).uppercased()) · \(Int(order.total)) сомони")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
                Spacer()
            }
            Text("Отменён курьером — \(reasonText)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var statusIcon: String {
        switch order.status {
        case .created:            return "bell.fill"
        case .accepted:           return "checkmark.circle"
        case .preparing:          return "flame"
        case .ready:              return "bag.fill"
        case .assigned:           return "bicycle"
        case .courierArrivedRestaurant: return "figure.wave"
        case .pickedUp:           return "shippingbox.fill"
        case .scheduled:          return "calendar"
        case .cancelledByCourier: return "xmark.octagon.fill"
        case .cancelledBySystem:  return "exclamationmark.triangle.fill"
        default:                  return "circle"
        }
    }

    private var statusColor: Color {
        switch order.status {
        case .created:   return .orange
        case .accepted:  return .blue
        case .preparing: return .purple
        case .ready:     return .green
        case .assigned:  return .teal
        case .courierArrivedRestaurant: return .orange
        case .scheduled: return .blue
        case .cancelled, .cancelledByCustomer, .cancelledByRestaurant,
             .cancelledBySystem, .cancelledByCourier, .rejected:
            return .red
        default:         return .gray
        }
    }
}

// MARK: - Scheduled Order Row (read-only)

struct ScheduledOrderRow: View {
    let order: Order

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Запланирован", systemImage: "calendar")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.blue)
                Spacer()
                Text("\(Int(order.total)) сомони")
                    .font(.headline)
                    .foregroundStyle(Color.ravonRed)
            }
            HStack {
                Text("Заказ #\(order.id.uuidString.prefix(6).uppercased())")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let when = order.scheduledFor {
                    Text(when.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let items = order.orderItems, !items.isEmpty {
                Text(items.map { "\($0.itemName) x\($0.quantity)" }.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Text("Платформа автоматически переведёт заказ в активные за время приготовления до указанного времени.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}
