import SwiftUI
import Combine
import RavonCore
import AudioToolbox
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class OrdersViewModel: ObservableObject {
    @Published var orders: [Order] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var hasNewOrderAlert = false

    let restaurantId: UUID
    private var cancellables = Set<AnyCancellable>()

    init(restaurantId: UUID) {
        self.restaurantId = restaurantId
    }

    var newOrders: [Order] {
        orders.filter { $0.status == .created }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var activeOrders: [Order] {
        orders
            .filter { isActiveOrSurfacedTerminal($0) }
            .sorted { lhs, rhs in
                // Cancelled-by-courier and auto-cancelled bubble to top so the merchant
                // sees food that needs handling before the rest of the queue.
                let lhsAttention = needsAttention(lhs)
                let rhsAttention = needsAttention(rhs)
                if lhsAttention != rhsAttention { return lhsAttention }
                return lhs.createdAt > rhs.createdAt
            }
    }

    var readyOrders: [Order] {
        orders.filter { $0.status == .ready }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private func isActiveOrSurfacedTerminal(_ order: Order) -> Bool {
        switch order.status {
        case .accepted, .preparing:
            return true
        case .cancelledByCourier:
            return true
        case .cancelledBySystem:
            // Surface only the auto-cancel-for-restaurant-too-long terminal — that's the
            // one the merchant gets paid 50% for and needs to see in the queue.
            return order.cancellationReasonCode == CancellationReason.restaurantTooLongWait.rawValue
        default:
            return false
        }
    }

    private func needsAttention(_ order: Order) -> Bool {
        order.status == .cancelledByCourier
            || (order.status == .cancelledBySystem
                && order.cancellationReasonCode == CancellationReason.restaurantTooLongWait.rawValue)
    }

    /// Orders the consumer scheduled for later. Read-only here — `activate_scheduled_orders`
    /// (server cron) flips them to `.created` automatically when prep-time before scheduledFor.
    var scheduledOrders: [Order] {
        orders.filter { $0.status == .scheduled }
            .sorted { ($0.scheduledFor ?? .distantFuture) < ($1.scheduledFor ?? .distantFuture) }
    }

    func startListening() async {
        do {
            try await RealtimeService.shared.subscribeToRestaurantOrders(restaurantId: restaurantId)
        } catch {
            errorMessage = error.localizedDescription
        }

        RealtimeService.shared.$lastOrderChange
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { [weak self] in
                    await self?.fetchOrders(silent: true)
                }
            }
            .store(in: &cancellables)
    }

    func stopListening() {
        Task {
            await RealtimeService.shared.unsubscribeFromOrders()
        }
        cancellables.removeAll()
    }

    func fetchOrders(silent: Bool = false) async {
        if !silent { isLoading = true }

        do {
            let fetched = try await SupabaseService.shared.fetchOrdersForRestaurant(restaurantId: restaurantId)

            let previousCreatedIds = Set(orders.filter { $0.status == .created }.map(\.id))
            let newCreatedIds = Set(fetched.filter { $0.status == .created }.map(\.id))
            let brandNewOrders = newCreatedIds.subtracting(previousCreatedIds)

            orders = fetched

            if !brandNewOrders.isEmpty && !previousCreatedIds.isEmpty {
                alertNewOrder()
                hasNewOrderAlert = true
            }
        } catch {
            if !silent { errorMessage = error.localizedDescription }
        }

        if !silent { isLoading = false }
    }

    func acceptOrder(_ orderId: UUID, estimatedPrepTime: Int) async {
        do {
            try await SupabaseService.shared.acceptOrder(orderId: orderId, estimatedPrepMinutes: estimatedPrepTime)
            await fetchOrders(silent: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func rejectOrder(_ orderId: UUID, reason: String) async {
        do {
            try await SupabaseService.shared.rejectOrder(orderId: orderId, reason: reason)
            await fetchOrders(silent: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func advanceOrder(_ orderId: UUID, currentStatus: OrderStatus) async {
        do {
            switch currentStatus {
            case .accepted:
                try await SupabaseService.shared.startPreparing(orderId: orderId)
            case .preparing:
                try await SupabaseService.shared.markOrderReady(orderId: orderId)
            default:
                return
            }
            await fetchOrders(silent: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cancelOrder(_ orderId: UUID, reason: String) async {
        do {
            try await SupabaseService.shared.cancelOrder(orderId: orderId, reason: reason)
            await fetchOrders(silent: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Private

    private func alertNewOrder() {
        AudioServicesPlayAlertSound(SystemSoundID(1005))
        #if canImport(UIKit)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
        #endif
    }
}
