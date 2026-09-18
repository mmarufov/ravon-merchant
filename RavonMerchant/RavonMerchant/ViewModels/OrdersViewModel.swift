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

    /// Queue-level failures — loading the list, subscribing to realtime. Rendered as an
    /// alert by `OrdersView`.
    @Published var listError: String?

    /// Failures from the four order actions. Rendered inline by `OrderDetailView` and
    /// inside its sheets, never as an alert: the sheet has to stay open so the merchant can
    /// read what went wrong and retry. Previously these were assigned to an `errorMessage`
    /// that no view read, so accept/reject/cancel failed in complete silence.
    @Published var actionError: String?

    @Published var hasNewOrderAlert = false

    let restaurantId: UUID
    private var cancellables = Set<AnyCancellable>()

    init(restaurantId: UUID) {
        self.restaurantId = restaurantId
    }

    // MARK: - Queue buckets

    /// Every order the merchant may see, bucketed. A visible order always lands in exactly
    /// one bucket — `MerchantOrderVisibilityTests` asserts the partition is total, which is
    /// the regression test for orders vanishing from the queue mid-hand-off.
    func orders(in bucket: MerchantQueueBucket) -> [Order] {
        let matching = orders.filter { MerchantQueueBucket.bucket(for: $0) == bucket }
        switch bucket {
        case .new:
            return matching.sorted { $0.createdAt > $1.createdAt }
        case .active:
            return matching.sorted { lhs, rhs in
                // Cancelled-by-courier and auto-cancelled bubble to top so the merchant
                // sees food that needs handling before the rest of the queue.
                let lhsAttention = MerchantOrderVisibility.isSurfacedTerminal(lhs)
                let rhsAttention = MerchantOrderVisibility.isSurfacedTerminal(rhs)
                if lhsAttention != rhsAttention { return lhsAttention }
                return lhs.createdAt > rhs.createdAt
            }
        case .handoff:
            return matching.sorted { lhs, rhs in
                // A courier standing at the counter outranks one still riding over, which
                // outranks food waiting for anybody. Oldest first within a rank: that
                // order has been sitting on the shelf longest.
                let lhsRank = handoffUrgency(lhs.status)
                let rhsRank = handoffUrgency(rhs.status)
                if lhsRank != rhsRank { return lhsRank > rhsRank }
                return lhs.createdAt < rhs.createdAt
            }
        case .scheduled:
            return matching.sorted { ($0.scheduledFor ?? .distantFuture) < ($1.scheduledFor ?? .distantFuture) }
        }
    }

    var newOrders: [Order] { orders(in: .new) }
    var activeOrders: [Order] { orders(in: .active) }
    /// Ready, claimed, and courier-at-the-counter. Formerly `.ready` only, which is why the
    /// order left every tab the moment a courier claimed it.
    var handoffOrders: [Order] { orders(in: .handoff) }
    /// Orders the consumer scheduled for later. Read-only here — `activate_scheduled_orders`
    /// (server cron) flips them to `.created` automatically when prep-time before scheduledFor.
    var scheduledOrders: [Order] { orders(in: .scheduled) }

    /// Orders where a courier is waiting or on the way, across all buckets. The counter
    /// needs this to be loud.
    var ordersInHandoff: [Order] {
        orders.filter(\.isInMerchantHandoff)
    }

    private func handoffUrgency(_ status: OrderStatus) -> Int {
        switch status {
        case .courierArrivedRestaurant: return 2
        case .assigned:                 return 1
        default:                        return 0
        }
    }

    // MARK: - Realtime

    func startListening() async {
        do {
            try await RealtimeService.shared.subscribeToRestaurantOrders(restaurantId: restaurantId)
        } catch {
            listError = MerchantError.message(for: error)
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

    // MARK: - Data

    /// `silent` suppresses the spinner, not the error: a refetch that fails after a
    /// successful mutation used to leave a stale row on screen with no indication at all.
    func fetchOrders(silent: Bool = false) async {
        if !silent { isLoading = true }
        listError = nil

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
            listError = MerchantError.message(for: error)
        }

        if !silent { isLoading = false }
    }

    // MARK: - Order actions

    /// The four actions return whether they succeeded, so a sheet can stay open on failure
    /// instead of dismissing unconditionally over a swallowed error.
    @discardableResult
    func acceptOrder(_ orderId: UUID, estimatedPrepTime: Int) async -> Bool {
        await perform {
            try await SupabaseService.shared.acceptOrder(orderId: orderId, estimatedPrepMinutes: estimatedPrepTime)
        }
    }

    @discardableResult
    func rejectOrder(_ orderId: UUID, reason: String) async -> Bool {
        await perform {
            try await SupabaseService.shared.rejectOrder(orderId: orderId, reason: reason)
        }
    }

    @discardableResult
    func advanceOrder(_ orderId: UUID, currentStatus: OrderStatus) async -> Bool {
        switch currentStatus {
        case .accepted:
            return await perform {
                try await SupabaseService.shared.startPreparing(orderId: orderId)
            }
        case .preparing:
            return await perform {
                try await SupabaseService.shared.markOrderReady(orderId: orderId)
            }
        default:
            return false
        }
    }

    /// Blocked on the backend: `merchant_cancel_order` does not exist. The old
    /// implementation called `cancel_order_by_consumer` — the consumer's RPC, which rejects
    /// a merchant caller — and the sheet dismissed over the error, so the merchant was told
    /// the order was cancelled when nothing had happened. Refuse locally and say so instead
    /// of issuing a call we know the server will reject.
    @discardableResult
    func cancelOrder(_ orderId: UUID, reason: String) async -> Bool {
        guard MerchantBackendGap.merchantCancelAvailable else {
            actionError = MerchantBackendGap.merchantCancelUnavailableMessage
            return false
        }
        return await perform {
            try await SupabaseService.shared.cancelOrder(orderId: orderId, reason: reason)
        }
    }

    func clearActionError() {
        actionError = nil
    }

    private func perform(_ operation: () async throws -> Void) async -> Bool {
        actionError = nil
        do {
            try await operation()
            await fetchOrders(silent: true)
            return true
        } catch {
            actionError = MerchantError.message(for: error, in: .orderAction)
            return false
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
