import SwiftUI
import RavonCore

struct OrdersView: View {
    @StateObject private var vm: OrdersViewModel
    @State private var selectedTab = 0

    init(restaurantId: UUID) {
        _vm = StateObject(wrappedValue: OrdersViewModel(restaurantId: restaurantId))
    }

    private var currentOrders: [Order] {
        switch selectedTab {
        case 0: return vm.newOrders
        case 1: return vm.activeOrders
        case 2: return vm.readyOrders
        case 3: return vm.scheduledOrders
        default: return []
        }
    }

    private var emptyMessage: String {
        switch selectedTab {
        case 0: return "Новых заказов нет"
        case 1: return "Нет активных заказов"
        case 2: return "Нет готовых заказов"
        case 3: return "Нет запланированных заказов"
        default: return ""
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $selectedTab) {
                    Text("Новые (\(vm.newOrders.count))").tag(0)
                    Text("В работе (\(vm.activeOrders.count))").tag(1)
                    Text("Готовые (\(vm.readyOrders.count))").tag(2)
                    Text("Запланированные (\(vm.scheduledOrders.count))").tag(3)
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
                        selectedTab == 3 ? "Нет запланированных" : "Нет заказов",
                        systemImage: selectedTab == 3 ? "calendar" : "tray",
                        description: Text(emptyMessage)
                    )
                    Spacer()
                } else {
                    List(currentOrders) { order in
                        if selectedTab == 3 {
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
        }
    }
}

// MARK: - Order Row

struct OrderRowView: View {
    let order: Order

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Заказ #\(order.id.uuidString.prefix(6).uppercased())")
                    .font(.headline)
                Spacer()
                Text("\(Int(order.total)) сум")
                    .font(.headline)
                    .foregroundStyle(Color.ravonRed)
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

            if let items = order.orderItems, !items.isEmpty {
                Text(items.map { "\($0.itemName) x\($0.quantity)" }.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusIcon: String {
        switch order.status {
        case .created:   return "bell.fill"
        case .accepted:  return "checkmark.circle"
        case .preparing: return "flame"
        case .ready:     return "bag.fill"
        case .scheduled: return "calendar"
        default:         return "circle"
        }
    }

    private var statusColor: Color {
        switch order.status {
        case .created:   return .orange
        case .accepted:  return .blue
        case .preparing: return .purple
        case .ready:     return .green
        case .scheduled: return .blue
        case .cancelled: return .red
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
                Text("\(Int(order.total)) сум")
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
