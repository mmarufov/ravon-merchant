import SwiftUI
import Combine
import RavonCore

struct DashboardView: View {
    @StateObject private var vm: DashboardViewModel
    @State private var showAcceptingSheet = false
    @State private var showPauseAlert = false

    init(restaurant: Restaurant) {
        _vm = StateObject(wrappedValue: DashboardViewModel(restaurant: restaurant))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    consumerPreviewPill
                    headerCard
                    acceptingPill
                    if let stats = vm.stats {
                        statsGrid(stats)
                    } else if vm.isLoading {
                        ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                    }
                }
                .padding()
            }
            .navigationTitle("Дашборд")
            .refreshable { await vm.refresh() }
            .task { await vm.start() }
            .onDisappear { vm.stop() }
            .sheet(isPresented: $showAcceptingSheet) {
                AcceptingOrdersSheet(
                    isCurrentlyAccepting: vm.restaurant.isAcceptingOrders,
                    acceptingOrdersUntil: vm.restaurant.acceptingOrdersUntil,
                    isBusy: vm.isMutatingStatus,
                    errorMessage: vm.errorMessage,
                    onPickPreset: { interval in
                        let until = interval.map { Date().addingTimeInterval($0) }
                        return await vm.setAcceptingOrders(accepting: false, until: until)
                    },
                    onResume: {
                        await vm.setAcceptingOrders(accepting: true, until: nil)
                    }
                )
            }
            .alert("Приостановить ресторан?", isPresented: $showPauseAlert) {
                Button("Приостановить", role: .destructive) {
                    Task { await vm.pauseRestaurant() }
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Клиенты перестанут видеть ваш ресторан. Возобновить можно в любой момент.")
            }
            .errorAlert($vm.errorMessage, suppressed: showAcceptingSheet)
        }
    }

    // MARK: - Consumer preview pill

    @ViewBuilder
    private var consumerPreviewPill: some View {
        let preview = previewState
        HStack(alignment: .top, spacing: 10) {
            Text(preview.icon).font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(preview.title)
                    .font(.subheadline.weight(.semibold))
                if let sub = preview.subtitle {
                    Text(sub).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12).fill(preview.tint.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12).stroke(preview.tint.opacity(0.35), lineWidth: 1)
        )
    }

    private struct PreviewState {
        let icon: String
        let title: String
        let subtitle: String?
        let tint: Color
    }

    private var previewState: PreviewState {
        let r = vm.restaurant
        switch r.restaurantStatus {
        case .closed:
            return .init(icon: "❌", title: "Закрыто навсегда", subtitle: nil, tint: .red)
        case .draft:
            return .init(icon: "📝", title: "Черновик — ещё не опубликован", subtitle: "Завершите настройку и нажмите \"Открыть ресторан\"", tint: .gray)
        case .paused:
            return .init(icon: "🌙", title: "Приостановлено — клиенты не видят вас",
                         subtitle: "Возобновите работу в \"Настройках\"", tint: .orange)
        case .active:
            if !r.isAcceptingOrders {
                let sub: String
                if let until = r.acceptingOrdersUntil {
                    sub = "Клиенты видят вас, но не могут заказать до \(vm.formatUntil(until))"
                } else {
                    sub = "Клиенты видят вас, но не могут заказать"
                }
                return .init(icon: "⏸", title: "Не принимаете заказы", subtitle: sub, tint: .orange)
            }
            if vm.isWithinHours {
                return .init(icon: "✅", title: "Сейчас вас видят и могут заказать", subtitle: nil, tint: .green)
            }
            let sub: String
            if let next = vm.nextOpeningTime {
                sub = "Клиенты могут запланировать заказ — откроетесь в \(next)"
            } else {
                sub = "Клиенты могут запланировать заказ на позже"
            }
            return .init(icon: "⏰", title: "Сейчас закрыто по расписанию", subtitle: sub, tint: .blue)
        }
    }

    // MARK: - Header card (name + status row)

    private var headerCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(vm.restaurant.name).font(.headline)
                HStack(spacing: 6) {
                    Circle().fill(statusColor).frame(width: 10, height: 10)
                    Text(statusText).font(.subheadline).foregroundStyle(statusColor)
                }
            }
            Spacer()
            statusActionButton
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }

    @ViewBuilder
    private var statusActionButton: some View {
        switch vm.restaurant.restaurantStatus {
        case .active:
            Button("Приостановить") { showPauseAlert = true }
                .buttonStyle(.bordered)
                .tint(.orange)
                .disabled(vm.isMutatingStatus)
        case .paused:
            Button("Возобновить") { Task { await vm.resumeRestaurant() } }
                .buttonStyle(.borderedProminent)
                .tint(Color.ravonRed)
                .disabled(vm.isMutatingStatus)
        case .draft, .closed:
            EmptyView()
        }
    }

    // MARK: - Accepting-orders pill

    @ViewBuilder
    private var acceptingPill: some View {
        if vm.restaurant.restaurantStatus == .active {
            Button { showAcceptingSheet = true } label: {
                HStack(spacing: 12) {
                    Circle()
                        .fill(vm.restaurant.isAcceptingOrders ? Color.green : Color.red)
                        .frame(width: 12, height: 12)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(vm.restaurant.isAcceptingOrders ? "Принимаете заказы" : "Не принимаете")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                        if !vm.restaurant.isAcceptingOrders, let until = vm.restaurant.acceptingOrdersUntil {
                            Text("до \(vm.formatUntil(until))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if vm.restaurant.isAcceptingOrders {
                            Text("Нажмите, чтобы временно остановить")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Нажмите, чтобы возобновить")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
                .padding()
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Stats

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
            HStack { Image(systemName: icon).foregroundStyle(color); Spacer() }
            Text(value).font(.title2.bold()).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }

    // MARK: - Helpers

    private var statusColor: Color {
        switch vm.restaurant.restaurantStatus {
        case .active: return .green
        case .paused: return .orange
        case .draft:  return .gray
        case .closed: return .red
        }
    }

    private var statusText: String {
        switch vm.restaurant.restaurantStatus {
        case .active: return "Активен"
        case .paused: return "Приостановлен"
        case .draft:  return "Черновик"
        case .closed: return "Закрыт"
        }
    }

    private func formatCurrency(_ value: Double) -> String { "\(Int(value)) сомони" }
}
