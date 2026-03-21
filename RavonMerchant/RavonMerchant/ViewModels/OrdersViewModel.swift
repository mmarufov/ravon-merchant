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
        orders.filter { !$0.status.isTerminal && $0.status != .created }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var readyOrders: [Order] {
        orders.filter { $0.status == .ready }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func subscribe() {
        RealtimeService.shared.subscribeToRestaurantOrders(restaurantId: restaurantId)

        RealtimeService.shared.lastOrderChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                guard let self else { return }
                if change.oldStatus == nil {
                    // New order inserted
                    alertNewOrder()
                    hasNewOrderAlert = true
                }
                Task { await self.fetchOrders(silent: true) }
            }
            .store(in: &cancellables)
    }

    func unsubscribe() {
        cancellables.removeAll()
    }

    func fetchOrders(silent: Bool = false) async {
        if !silent { isLoading = true }

        do {
            let fetched = try await SupabaseService.shared.fetchOrdersForRestaurant(restaurantId: restaurantId)
            orders = fetched
        } catch {
            if !silent { errorMessage = error.localizedDescription }
        }

        if !silent { isLoading = false }
    }

    func acceptOrder(_ orderId: UUID, estimatedPrepMinutes: Int) async {
        do {
            try await SupabaseService.shared.acceptOrder(orderId: orderId, estimatedPrepMinutes: estimatedPrepMinutes)
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
                try await SupabaseService.shared.updateOrderStatus(orderId: orderId, status: .preparing)
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

    // MARK: - Private

    private func alertNewOrder() {
        AudioServicesPlayAlertSound(SystemSoundID(1005))
        #if canImport(UIKit)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
        #endif
    }
}
