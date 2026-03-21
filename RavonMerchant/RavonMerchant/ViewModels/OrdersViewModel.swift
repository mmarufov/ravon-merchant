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
    private var refreshTimer: Timer?

    init(restaurantId: UUID) {
        self.restaurantId = restaurantId
    }

    var newOrders: [Order] {
        orders.filter { $0.status == .created }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var activeOrders: [Order] {
        orders.filter { $0.status == .accepted || $0.status == .preparing }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var readyOrders: [Order] {
        orders.filter { $0.status == .ready }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func startPolling() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.fetchOrders(silent: true)
            }
        }
    }

    func stopPolling() {
        refreshTimer?.invalidate()
        refreshTimer = nil
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

    func acceptOrder(_ orderId: UUID, estimatedPrepMinutes: Int) async {
        // TODO: Use SupabaseService.shared.acceptOrder(orderId:estimatedPrepMinutes:) when RavonCore is updated
        await updateStatus(orderId: orderId, to: .accepted)
    }

    func rejectOrder(_ orderId: UUID, reason: String) async {
        // TODO: Use SupabaseService.shared.rejectOrder(orderId:reason:) when RavonCore is updated
        await updateStatus(orderId: orderId, to: .cancelled)
    }

    func advanceOrder(_ orderId: UUID, currentStatus: OrderStatus) async {
        guard let next = nextStatus(for: currentStatus) else { return }
        // TODO: For .preparing → .ready, use SupabaseService.shared.markOrderReady(orderId:) when RavonCore is updated
        await updateStatus(orderId: orderId, to: next)
    }

    // MARK: - Private

    private func updateStatus(orderId: UUID, to status: OrderStatus) async {
        do {
            try await SupabaseService.shared.updateOrderStatus(orderId: orderId, status: status)
            await fetchOrders(silent: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func nextStatus(for status: OrderStatus) -> OrderStatus? {
        switch status {
        case .created: return .accepted
        case .accepted: return .preparing
        case .preparing: return .ready
        default: return nil
        }
    }

    private func alertNewOrder() {
        AudioServicesPlayAlertSound(SystemSoundID(1005))
        #if canImport(UIKit)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
        #endif
    }
}
