import XCTest
import RavonCore
@testable import RavonMerchant

/// Regression tests for the hand-off blind spot.
///
/// The queue sourced its tabs from hand-written status lists: `.accepted`/`.preparing` for
/// "в работе" and `.ready` alone for "готовые". So the moment a courier claimed an order
/// (`.assigned`) it matched no tab, disappeared from the merchant's queue, and took the
/// detail screen with it — while the pickup-code gate, stopping at `.ready`, hid the code
/// the merchant has to read aloud.
final class MerchantOrderVisibilityTests: XCTestCase {

    private func order(
        _ status: OrderStatus,
        code: String? = "4821",
        reasonCode: String? = nil,
        createdAt: Date = Date()
    ) -> Order {
        Order(
            id: UUID(), userId: UUID(), restaurantId: UUID(),
            status: status, subtotal: 100, deliveryFee: 10, total: 110,
            createdAt: createdAt, updatedAt: createdAt,
            cancellationReasonCode: reasonCode,
            pickupVerificationCode: code
        )
    }

    // MARK: - Visibility

    func test_handoffStatusesAreVisibleToTheMerchant() {
        for status in [OrderStatus.assigned, .courierArrivedRestaurant] {
            XCTAssertTrue(order(status).isVisibleToMerchant,
                          "\(status.rawValue) must stay in the merchant's queue")
        }
    }

    /// The obligation is the reason the visibility exists — if RavonCore ever stops
    /// declaring it, this fails rather than silently re-hiding the order.
    func test_lifecycleDeclaresThePickupCodeObligationForTheWholeHandoffWindow() {
        for status in MerchantOrderVisibility.handoff {
            XCTAssertTrue(
                OrderLifecycle.obligations(for: .merchant, at: status).contains(.showPickupCode),
                "OrderLifecycle must oblige the merchant to show the pickup code at \(status.rawValue)"
            )
            XCTAssertTrue(OrderLifecycle.isVisible(status, to: .merchant))
        }
    }

    func test_everyLifecycleVisibleStatusLandsInExactlyOneBucket() {
        for status in MerchantOrderVisibility.lifecycleVisible {
            XCTAssertNotNil(
                MerchantQueueBucket.bucket(for: order(status)),
                "\(status.rawValue) is visible to the merchant but belongs to no tab"
            )
        }
    }

    func test_everyVisibleOrderLandsInABucket() {
        let samples: [Order] = OrderStatus.allCases.map { order($0) }
            + [order(.cancelledBySystem,
                     reasonCode: CancellationReason.restaurantTooLongWait.rawValue),
               order(.cancelledByCourier)]
        for sample in samples where sample.isVisibleToMerchant {
            XCTAssertNotNil(
                MerchantQueueBucket.bucket(for: sample),
                "\(sample.status.rawValue) is visible but unbucketed"
            )
        }
    }

    func test_invisibleOrdersAreNotBucketed() {
        for status in [OrderStatus.pickedUp, .delivering, .delivered, .cancelledByCustomer] {
            let sample = order(status)
            XCTAssertFalse(sample.isVisibleToMerchant, "\(status.rawValue)")
            XCTAssertNil(MerchantQueueBucket.bucket(for: sample), "\(status.rawValue)")
        }
    }

    func test_handoffBucketHoldsReadyAndBothHandoffStatuses() {
        for status in [OrderStatus.ready, .assigned, .courierArrivedRestaurant] {
            XCTAssertEqual(MerchantQueueBucket.bucket(for: order(status)), .handoff,
                           "\(status.rawValue) belongs in the hand-off tab")
        }
    }

    func test_surfacedTerminalsStayInTheActiveBucket() {
        XCTAssertEqual(MerchantQueueBucket.bucket(for: order(.cancelledByCourier)), .active)
        XCTAssertEqual(
            MerchantQueueBucket.bucket(for: order(
                .cancelledBySystem,
                reasonCode: CancellationReason.restaurantTooLongWait.rawValue
            )),
            .active
        )
        // A system cancel for any other reason is not the merchant's problem.
        XCTAssertNil(MerchantQueueBucket.bucket(for: order(.cancelledBySystem, reasonCode: "OTHER")))
    }

    // MARK: - Pickup code

    func test_pickupCodeIsVisibleThroughTheEntireHandoffWindow() {
        for status in [OrderStatus.preparing, .ready, .assigned, .courierArrivedRestaurant] {
            XCTAssertTrue(order(status).merchantShowsPickupCode,
                          "the code must be readable at \(status.rawValue)")
        }
    }

    func test_pickupCodeIsHiddenBeforeAcceptanceAndAfterPickup() {
        for status in [OrderStatus.created, .scheduled, .pickedUp, .delivered] {
            XCTAssertFalse(order(status).merchantShowsPickupCode, "\(status.rawValue)")
        }
    }

    func test_noPickupCodeMeansNothingToShow() {
        XCTAssertFalse(order(.assigned, code: nil).merchantShowsPickupCode)
    }

    // MARK: - Bucket contents through the view model

    @MainActor
    func test_viewModelKeepsTheOrderVisibleAcrossTheWholeHandoff() async {
        let vm = OrdersViewModel(restaurantId: UUID())
        let statuses: [OrderStatus] = [.accepted, .preparing, .ready, .assigned, .courierArrivedRestaurant]
        for status in statuses {
            vm.orders = [order(status)]
            let visible = MerchantQueueBucket.allCases.flatMap { vm.orders(in: $0) }
            XCTAssertEqual(visible.count, 1, "order vanished from every tab at \(status.rawValue)")
        }
    }

    @MainActor
    func test_handoffTabPutsTheCourierAtTheCounterFirst() {
        let vm = OrdersViewModel(restaurantId: UUID())
        let now = Date()
        let ready = order(.ready, createdAt: now)
        let assigned = order(.assigned, createdAt: now.addingTimeInterval(-60))
        let arrived = order(.courierArrivedRestaurant, createdAt: now.addingTimeInterval(-30))
        vm.orders = [ready, assigned, arrived]

        XCTAssertEqual(vm.handoffOrders.map(\.id), [arrived.id, assigned.id, ready.id])
    }

    // MARK: - The backend gap

    /// `merchant_cancel_order` has no RPC yet, so the UI must say so rather than call the
    /// consumer's RPC and fail silently. When core ships it, this test flips and the guard
    /// in `OrdersViewModel.cancelOrder` stops firing — both read the same lifecycle data.
    func test_merchantCancelIsReportedUnavailableWhileTheRPCIsMissing() {
        XCTAssertEqual(
            MerchantBackendGap.merchantCancelAvailable,
            !OrderLifecycle.unimplementedRPCs.contains("merchant_cancel_order")
        )
    }

    @MainActor
    func test_cancelSurfacesAnErrorInsteadOfCallingTheConsumerRPC() async throws {
        try XCTSkipIf(MerchantBackendGap.merchantCancelAvailable,
                       "merchant_cancel_order now exists — this guard is obsolete")
        let vm = OrdersViewModel(restaurantId: UUID())
        let succeeded = await vm.cancelOrder(UUID(), reason: "нет ингредиентов")
        XCTAssertFalse(succeeded)
        XCTAssertEqual(vm.actionError, MerchantBackendGap.merchantCancelUnavailableMessage)
    }
}
