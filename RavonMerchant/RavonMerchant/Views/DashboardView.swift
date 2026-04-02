import SwiftUI
import Combine
import RavonCore

struct DashboardView: View {
    let restaurant: Restaurant
    @State private var stats: MerchantStats?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var currentRestaurant: Restaurant
    @State private var isTogglingStatus = false
    @State private var timer: Timer?

    init(restaurant: Restaurant) {
        self.restaurant = restaurant
        _currentRestaurant = State(initialValue: restaurant)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Status badge
                    statusSection

                    // Stats grid
                    if let stats {
                        statsGrid(stats)
                    } else if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 200)
                    }
                }
                .padding()
            }
            .navigationTitle("Дашборд")
            .refreshable {
                await loadData()
            }
            .task {
                await loadData()
                startAutoRefresh()
            }
            .onDisappear {
                timer?.invalidate()
                timer = nil
            }
            .alert("Ошибка", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - Status Section

    private var statusSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(currentRestaurant.name)
                    .font(.headline)
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 10, height: 10)
                    Text(statusText)
                        .font(.subheadline)
                        .foregroundStyle(statusColor)
                }
            }

            Spacer()

            if currentRestaurant.restaurantStatus == .active {
                Button("Приостановить") {
                    Task { await toggleStatus() }
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .disabled(isTogglingStatus)
            } else if currentRestaurant.restaurantStatus == .paused {
                Button("Возобновить") {
                    Task { await toggleStatus() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.ravonRed)
                .disabled(isTogglingStatus)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }

    // MARK: - Stats Grid

    private func statsGrid(_ stats: MerchantStats) -> some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ], spacing: 12) {
            statCard(title: "Заказы сегодня", value: "\(stats.todayOrderCount)", icon: "list.clipboard", color: .blue)
            statCard(title: "Выручка", value: formatCurrency(stats.todayRevenue), icon: "banknote", color: .green)
            statCard(title: "Средний чек", value: formatCurrency(stats.averageOrderValue), icon: "chart.bar", color: .purple)
            statCard(title: "Активные заказы", value: "\(stats.activeOrderCount)", icon: "clock", color: .orange)
        }
    }

    private func statCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Spacer()
            }
            Text(value)
                .font(.title2.bold())
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }

    // MARK: - Helpers

    private var statusColor: Color {
        switch currentRestaurant.restaurantStatus {
        case .active: return .green
        case .paused: return .orange
        case .draft: return .gray
        case .closed: return .red
        }
    }

    private var statusText: String {
        switch currentRestaurant.restaurantStatus {
        case .active: return "Активен"
        case .paused: return "Приостановлен"
        case .draft: return "Черновик"
        case .closed: return "Закрыт"
        }
    }

    private func formatCurrency(_ value: Double) -> String {
        "\(Int(value)) сум"
    }

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }

        do {
            stats = try await SupabaseService.shared.fetchMerchantStats(restaurantId: restaurant.id)
            if let updated = try await SupabaseService.shared.fetchMyRestaurant() {
                currentRestaurant = updated
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleStatus() async {
        isTogglingStatus = true
        defer { isTogglingStatus = false }

        do {
            if currentRestaurant.restaurantStatus == .active {
                try await SupabaseService.shared.pauseRestaurant(id: restaurant.id)
            } else if currentRestaurant.restaurantStatus == .paused {
                try await SupabaseService.shared.resumeRestaurant(id: restaurant.id)
            }
            if let updated = try await SupabaseService.shared.fetchMyRestaurant() {
                currentRestaurant = updated
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startAutoRefresh() {
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            Task { @MainActor in
                do {
                    stats = try await SupabaseService.shared.fetchMerchantStats(restaurantId: restaurant.id)
                } catch {}
            }
        }
    }
}
