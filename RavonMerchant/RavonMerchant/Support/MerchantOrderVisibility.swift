import Foundation
import RavonCore

/// What the merchant may see, and when the pickup code must be on screen.
///
/// This used to be a hand-written status array per screen, and the copies disagreed: the
/// queue dropped an order at `.assigned` while the pickup-code gate stopped at `.ready`,
/// so the app went blind for the whole hand-off window — precisely when the courier was at
/// the counter asking for the code the merchant has to read out.
///
/// Everything below is derived from `OrderLifecycle` (RavonCore ≥ 0.9.0), which declares
/// the merchant's *obligation* to show the pickup code at `.assigned` and
/// `.courierArrivedRestaurant`. Visibility follows from the obligation instead of being
/// restated, so the two cannot drift apart again.
enum MerchantOrderVisibility {

    /// Statuses the merchant can act on plus every status it carries an obligation at.
    nonisolated static let lifecycleVisible: Set<OrderStatus> =
        OrderLifecycle.visibleStatuses(for: .merchant)

    /// The hand-off window: courier is en route to, or standing at, the counter.
    nonisolated static let handoff: Set<OrderStatus> = [.assigned, .courierArrivedRestaurant]

    /// Terminal statuses the merchant is shown anyway because money or food is at stake
    /// and someone has to deal with it. Not part of the lifecycle's visibility set —
    /// nothing is actionable — so it stays an explicit app-level decision.
    nonisolated static func isSurfacedTerminal(_ order: Order) -> Bool {
        switch order.status {
        case .cancelledByCourier:
            return true
        case .cancelledBySystem:
            // Only the auto-cancel-for-restaurant-too-long terminal: that is the one the
            // merchant gets paid 50% for and needs to see in the queue.
            return order.cancellationReasonCode == CancellationReason.restaurantTooLongWait.rawValue
        default:
            return false
        }
    }
}

extension Order {

    /// True if this order belongs in the merchant's queue at all. Every visible order must
    /// land in exactly one `MerchantQueueBucket`; `MerchantOrderVisibilityTests` asserts it.
    var isVisibleToMerchant: Bool {
        MerchantOrderVisibility.lifecycleVisible.contains(status)
            || status == .scheduled
            || MerchantOrderVisibility.isSurfacedTerminal(self)
    }

    /// The courier is on the way to the counter, or already there.
    var isInMerchantHandoff: Bool {
        MerchantOrderVisibility.handoff.contains(status)
    }

    /// Whether the pickup code should be on screen.
    ///
    /// `OrderLifecycle` makes showing it an obligation for the whole hand-off window;
    /// `.preparing` / `.ready` are added on top because the code exists earlier and a
    /// counter benefits from seeing it before the courier walks in. `courier_pickup_order`
    /// takes the code from the *courier*, so the merchant is the one who reads it aloud.
    var merchantShowsPickupCode: Bool {
        guard pickupVerificationCode != nil else { return false }
        let obliged = OrderLifecycle
            .obligations(for: .merchant, at: status)
            .contains(.showPickupCode)
        return obliged || status == .preparing || status == .ready
    }
}

/// The tabs of the order queue. Exhaustive over `Order.isVisibleToMerchant`.
enum MerchantQueueBucket: Int, CaseIterable {
    /// Needs a decision: accept or reject.
    case new = 0
    /// In the kitchen — plus the cancelled orders that need handling.
    case active = 1
    /// Cooked and waiting for, or being handed to, a courier. The hand-off window lives
    /// here rather than in its own tab: it is where the merchant already looks when a
    /// courier walks in.
    case handoff = 2
    /// Scheduled by the consumer for later. Read-only.
    case scheduled = 3

    var title: String {
        switch self {
        case .new:       return "Новые"
        case .active:    return "В работе"
        case .handoff:   return "Выдача"
        case .scheduled: return "Запланированные"
        }
    }

    var emptyMessage: String {
        switch self {
        case .new:       return "Новых заказов нет"
        case .active:    return "Нет активных заказов"
        case .handoff:   return "Нет заказов к выдаче"
        case .scheduled: return "Нет запланированных заказов"
        }
    }

    nonisolated static func bucket(for order: Order) -> MerchantQueueBucket? {
        if MerchantOrderVisibility.isSurfacedTerminal(order) { return .active }
        switch order.status {
        case .created:
            return .new
        case .accepted, .preparing:
            return .active
        case .ready, .assigned, .courierArrivedRestaurant:
            return .handoff
        case .scheduled:
            return .scheduled
        default:
            return nil
        }
    }
}
