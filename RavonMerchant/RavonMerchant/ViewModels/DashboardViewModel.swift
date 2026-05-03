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
        defer { isLoading = false }
        do {
            async let r = SupabaseService.shared.fetchMyRestaurant()
            async let h = SupabaseService.shared.fetchRestaurantHours(restaurantId: restaurant.id)
            async let s = SupabaseService.shared.fetchMerchantStats(restaurantId: restaurant.id)
            if let updated = try await r { restaurant = updated }
            hours = try await h
            stats = try await s
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func subscribe() async {
        do {
            try await RealtimeService.shared.subscribeToRestaurantStatus(restaurantId: restaurant.id)
        } catch {
            errorMessage = error.localizedDescription
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

    func setAcceptingOrders(accepting: Bool, until: Date?) async {
        isMutatingStatus = true
        defer { isMutatingStatus = false }
        do {
            try await SupabaseService.shared.setAcceptingOrders(
                restaurantId: restaurant.id, accepting: accepting, until: until
            )
            if let updated = try await SupabaseService.shared.fetchMyRestaurant() {
                restaurant = updated
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func mutateStatus(_ op: (UUID) async throws -> Void) async {
        isMutatingStatus = true
        defer { isMutatingStatus = false }
        do {
            try await op(restaurant.id)
            if let updated = try await SupabaseService.shared.fetchMyRestaurant() {
                restaurant = updated
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Hours / Preview State

    /// Current Душанбе weekday (0=Sun..6=Sat) and HH:mm:ss string.
    private static func dushanbeNow() -> (weekday: Int, hms: String, hourMinute: String) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Dushanbe") ?? .current
        let comps = cal.dateComponents([.weekday, .hour, .minute, .second], from: Date())
        let dow = ((comps.weekday ?? 1) - 1) % 7
        let h = comps.hour ?? 0, m = comps.minute ?? 0, s = comps.second ?? 0
        return (dow,
                String(format: "%02d:%02d:%02d", h, m, s),
                String(format: "%02d:%02d", h, m))
    }

    var isWithinHours: Bool {
        if hours.isEmpty { return true } // no rows → "always open" per server policy
        let now = Self.dushanbeNow()
        guard let today = hours.first(where: { $0.dayOfWeek == now.weekday }) else { return false }
        if today.isClosed { return false }
        return today.openingTime <= now.hms && now.hms < today.closingTime
    }

    /// Next opening time as HH:mm (Душанбе) within the next 7 days, or nil if hours are blank.
    var nextOpeningTime: String? {
        if hours.isEmpty { return nil }
        let now = Self.dushanbeNow()
        if let today = hours.first(where: { $0.dayOfWeek == now.weekday }),
           !today.isClosed, now.hms < today.openingTime {
            return String(today.openingTime.prefix(5))
        }
        for offset in 1...7 {
            let d = (now.weekday + offset) % 7
            if let row = hours.first(where: { $0.dayOfWeek == d }), !row.isClosed {
                return String(row.openingTime.prefix(5))
            }
        }
        return nil
    }

    /// "до HH:mm" formatted in Душанбе timezone for the dashboard sub-line.
    func formatUntil(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "Asia/Dushanbe") ?? .current
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}
