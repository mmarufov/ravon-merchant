import SwiftUI
import Combine
import RavonCore

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var restaurant: Restaurant
    @Published var hours: [RestaurantHours] = []
    @Published var stats: MerchantStats?
    @Published var isLoading = false
    @Published var isMutatingStatus = false
    @Published var errorMessage: String?

    private var cancellables = Set<AnyCancellable>()
    private var refreshTimer: Timer?

    init(restaurant: Restaurant) {
        self.restaurant = restaurant
    }

    // MARK: - Lifecycle

    func start() async {
        await refresh()
        await subscribe()
        startStatsTimer()
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        cancellables.removeAll()
        Task { await RealtimeService.shared.unsubscribeFromRestaurantStatus() }
    }

    // MARK: - Data

    func refresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let r = SupabaseService.shared.fetchMyRestaurant()
            async let h = SupabaseService.shared.fetchRestaurantHours(restaurantId: restaurant.id)
            async let s = SupabaseService.shared.fetchMerchantStats(restaurantId: restaurant.id)
            if let updated = try await r { restaurant = updated }
            hours = try await h
            stats = try await s
        } catch {
            errorMessage = MerchantError.message(for: error)
        }
    }

    private func subscribe() async {
        do {
            try await RealtimeService.shared.subscribeToRestaurantStatus(restaurantId: restaurant.id)
        } catch {
            errorMessage = MerchantError.message(for: error)
            return
        }
        RealtimeService.shared.$lastRestaurantStatusChange
            .compactMap { $0 }
            .filter { [restaurantId = restaurant.id] in $0.restaurantId == restaurantId }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.refresh()
                }
            }
            .store(in: &cancellables)
    }

    private func startStatsTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.stats = try? await SupabaseService.shared.fetchMerchantStats(restaurantId: self.restaurant.id)
            }
        }
    }

    // MARK: - Lifecycle Mutations

    func pauseRestaurant() async {
        await mutateStatus { try await SupabaseService.shared.pauseRestaurant(id: $0) }
    }

    func resumeRestaurant() async {
        await mutateStatus { try await SupabaseService.shared.resumeRestaurant(id: $0) }
    }

    /// Returns whether the change stuck, so `AcceptingOrdersSheet` can stay open on
    /// failure instead of closing over an error the covered screen could not present.
    @discardableResult
    func setAcceptingOrders(accepting: Bool, until: Date?) async -> Bool {
        isMutatingStatus = true
        errorMessage = nil
        defer { isMutatingStatus = false }
        do {
            try await SupabaseService.shared.setAcceptingOrders(
                restaurantId: restaurant.id, accepting: accepting, until: until
            )
            if let updated = try await SupabaseService.shared.fetchMyRestaurant() {
                restaurant = updated
            }
            return true
        } catch {
            errorMessage = MerchantError.message(for: error)
            return false
        }
    }

    private func mutateStatus(_ op: (UUID) async throws -> Void) async {
        isMutatingStatus = true
        errorMessage = nil
        defer { isMutatingStatus = false }
        do {
            try await op(restaurant.id)
            if let updated = try await SupabaseService.shared.fetchMyRestaurant() {
                restaurant = updated
            }
        } catch {
            errorMessage = MerchantError.message(for: error)
        }
    }

    // MARK: - Hours / Preview State

    /// Whether the restaurant is inside its schedule right now.
    ///
    /// The logic lives in `[RestaurantHours].isOpen(at:)` so it can be tested against a
    /// fixed date — see `RestaurantOpenState.swift` for why the previous inline version
    /// reported a late-night restaurant as closed 24 hours a day, and for the `isOpen(at:)`
    /// request filed against RavonCore.
    var isWithinHours: Bool {
        hours.isOpen(at: Date())
    }

    /// Next opening time as HH:mm (Душанбе) within the next 7 days, or nil if hours are blank.
    var nextOpeningTime: String? {
        hours.nextOpening(at: Date())
    }

    /// "до HH:mm" formatted in Душанбе timezone for the dashboard sub-line.
    func formatUntil(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "Asia/Dushanbe") ?? .current
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}
