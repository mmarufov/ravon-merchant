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
        orders.filter { $0.status == .accepted || $0.status == .preparing }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var readyOrders: [Order] {
        orders.filter { $0.status == .ready }
            .sorted { $0.createdAt > $1.createdAt }
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
