import SwiftUI
import MapKit
import RavonCore
import Combine

struct OrderDetailView: View {
    let orderId: UUID
    @ObservedObject var vm: OrdersViewModel

    @State private var showAcceptSheet = false
    @State private var showRejectSheet = false
    @State private var showCancelSheet = false
    @State private var estimatedMinutes = 20
    @State private var rejectReason = ""
    @State private var cancelReason = ""
    @State private var courierPosition: CLLocationCoordinate2D?
    @State private var chatMessages: [ChatMessage] = []
    @State private var cancellables = Set<AnyCancellable>()

    /// Server convention: system messages on the escalation ladder are written
    /// with sender_id = zero UUID (verified by RavonCore ChatRLSCodingTests).
    private static let systemSenderId = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    private var order: Order? {
        vm.orders.first { $0.id == orderId }
    }

    var body: some View {
        Group {
            if let order {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        statusSection(order)

                        if isAutoCancelledForRestaurantTooLong(order) {
                            autoCancelAlertSection
                        }

                        if order.status == .cancelledByCourier {
                            cancelledByCourierSection(order)
                        }

                        if order.restaurantDelayMin > 0 {
                            restaurantDelaySection(order.restaurantDelayMin)
                        }

                        if order.reassignCount > 0 && !order.status.isTerminal {
                            reassignmentSection(order.reassignCount)
                        }

                        if [.preparing, .ready].contains(order.status),
                           let code = order.pickupVerificationCode {
                            pickupCodeSection(code)
                        }

                        if let courierId = order.courierId,
                           [.assigned, .courierArrivedRestaurant, .pickedUp, .delivering, .courierArrivedCustomer].contains(order.status) {
                            courierMapSection(courierId: courierId)
                        }

                        itemsSection(order)

                        if let address = order.deliveryAddressSnapshot {
                            deliverySection(address)
                        }

                        if let notes = order.notes, !notes.isEmpty {
                            notesSection(notes)
                        }

                        chatSection

                        actionsSection(order)
                    }
                    .padding()
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Заказ #\(orderId.uuidString.prefix(6).uppercased())")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAcceptSheet) {
            acceptSheet
        }
        .sheet(isPresented: $showRejectSheet) {
            rejectSheet
        }
        .sheet(isPresented: $showCancelSheet) {
            cancelSheet
        }
        .task {
            do {
                chatMessages = try await SupabaseService.shared.fetchMessages(orderId: orderId)
            } catch {
                chatMessages = []
            }

            do {
                try await RealtimeService.shared.subscribeToChat(orderId: orderId)
                RealtimeService.shared.$lastChatMessage
                    .compactMap { $0 }
                    .receive(on: DispatchQueue.main)
                    .sink { event in
                        if !chatMessages.contains(where: { $0.id == event.message.id }) {
                            chatMessages.append(event.message)
                        }
                    }
                    .store(in: &cancellables)
            } catch { /* read-only preview — silent on failure */ }

            guard let courierId = order?.courierId else { return }
            do {
                try await RealtimeService.shared.subscribeToCourierLocation(courierId: courierId)
            } catch { return }

            RealtimeService.shared.$lastCourierLocationChange
                .compactMap { $0 }
                .receive(on: DispatchQueue.main)
                .sink { event in
                    courierPosition = CLLocationCoordinate2D(
                        latitude: event.latitude,
                        longitude: event.longitude
                    )
                }
                .store(in: &cancellables)
        }
        .onDisappear {
            Task {
                await RealtimeService.shared.unsubscribeFromCourierLocation()
                await RealtimeService.shared.unsubscribeFromChat()
            }
            cancellables.removeAll()
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func statusSection(_ order: Order) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Статус")
                .font(.headline)
            Text(order.status.displayName)
                .font(.title3.bold())
                .foregroundStyle(statusColor(for: order.status))
            Text("Создан: \(order.createdAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 16)
    }

    @ViewBuilder
    private func pickupCodeSection(_ code: String) -> some View {
        VStack(spacing: 8) {
            Text("Готов к выдаче")
                .font(.headline)
            Text("Код для курьера: \(code)")
                .font(.system(size: 32, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.ravonRed)
            Text("Курьер назовёт этот код при получении")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .cardStyle(padding: 20)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.ravonRed.opacity(0.3), lineWidth: 2)
        )
    }

    @ViewBuilder
    private func restaurantDelaySection(_ minutes: Int) -> some View {
        HStack(spacing: 8) {
            Text("🕒 Курьер сообщил: задержка +\(minutes) мин (всего \(minutes)/30)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.orange)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func reassignmentSection(_ count: Int) -> some View {
        HStack(spacing: 8) {
            Text("↻ Поиск нового курьера (попытка \(count)/3)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.blue)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.blue.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var autoCancelAlertSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("⚠️ Заказ автоматически отменён")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.red)
            Text("Ресторан превысил время ожидания (30 мин). Курьер получил 50% оплаты.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.red.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.red.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func cancelledByCourierSection(_ order: Order) -> some View {
        let reasonText = CancellationReason(rawValue: order.cancellationReasonCode ?? "")?
            .localizedDisplayName ?? "Без причины"
        VStack(alignment: .leading, spacing: 4) {
            Text("Отменён курьером")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.red)
            Text(reasonText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.red.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var chatSection: some View {
        if !chatMessages.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Чат")
                    .font(.headline)
                ForEach(chatMessages) { message in
                    chatRow(message)
                    if message.id != chatMessages.last?.id {
                        Divider()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle(padding: 16)
        }
    }

    @ViewBuilder
    private func chatRow(_ message: ChatMessage) -> some View {
        if message.senderId == Self.systemSenderId {
            VStack(alignment: .leading, spacing: 2) {
                Text("🔔 Система")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(message.body)
                    .font(.subheadline.italic())
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text(message.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(message.body)
                    .font(.subheadline)
            }
        }
    }

    private func isAutoCancelledForRestaurantTooLong(_ order: Order) -> Bool {
        order.status == .cancelledBySystem
            && order.cancellationReasonCode == CancellationReason.restaurantTooLongWait.rawValue
    }

    @ViewBuilder
    private func courierMapSection(courierId: UUID) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Курьер на карте")
                .font(.headline)

            if let position = courierPosition {
                Map {
                    Annotation("Курьер", coordinate: position) {
                        Image(systemName: "figure.walk.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white)
                            .background(Circle().fill(Color.ravonRed).frame(width: 36, height: 36))
                    }
                }
                .mapStyle(.standard)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                HStack {
                    ProgressView()
                    Text("Ожидание геопозиции курьера...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 100)
            }
        }
        .cardStyle(padding: 16)
    }

    @ViewBuilder
    private func itemsSection(_ order: Order) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Позиции")
                .font(.headline)

            if let items = order.orderItems {
                ForEach(items) { item in
                    HStack {
                        Text(item.itemName)
                        Spacer()
                        Text("x\(item.quantity)")
                            .foregroundStyle(.secondary)
                        Text("\(Int(item.totalPrice)) сум")
                            .monospacedDigit()
                    }

                    if item.id != items.last?.id {
                        Divider()
                    }
                }

                Divider()

                HStack {
                    Text("Доставка")
                    Spacer()
                    Text("\(Int(order.deliveryFee)) сум")
                        .monospacedDigit()
                }
                .foregroundStyle(.secondary)

                HStack {
                    Text("Итого")
                        .fontWeight(.semibold)
                    Spacer()
                    Text("\(Int(order.total)) сум")
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
            }
        }
        .cardStyle(padding: 16)
    }

    @ViewBuilder
    private func deliverySection(_ address: AddressSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Доставка")
                .font(.headline)
            if let street = address.street {
                Text(street)
            }
            if let apt = address.apartment {
                Text("Кв. \(apt)")
                    .foregroundStyle(.secondary)
            }
            if let city = address.city {
                Text(city)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 16)
    }

    @ViewBuilder
    private func notesSection(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Комментарий")
                .font(.headline)
            Text(notes)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 16)
    }

    @ViewBuilder
    private func actionsSection(_ order: Order) -> some View {
        switch order.status {
        case .created:
            HStack(spacing: 12) {
                Button {
                    showRejectSheet = true
                } label: {
                    Text("Отклонить")
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .foregroundStyle(.red)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button {
                    showAcceptSheet = true
                } label: {
                    Text("Принять")
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.ravonRed)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }

        case .accepted:
            VStack(spacing: 12) {
                RavonPrimaryButton("Начать готовить") {
                    Task { await vm.advanceOrder(order.id, currentStatus: .accepted) }
                }
                cancelButton
            }

        case .preparing:
            VStack(spacing: 12) {
                RavonPrimaryButton("Готово") {
                    Task { await vm.advanceOrder(order.id, currentStatus: .preparing) }
                }
                cancelButton
            }

        case .ready:
            cancelButton

        default:
            EmptyView()
        }
    }

    private var cancelButton: some View {
        Button {
            showCancelSheet = true
        } label: {
            Text("Отменить заказ")
                .fontWeight(.medium)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.red.opacity(0.1))
                .foregroundStyle(.red)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Sheets

    private var acceptSheet: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Время приготовления")
                    .font(.headline)

                Stepper("\(estimatedMinutes) мин", value: $estimatedMinutes, in: 5...120, step: 5)
                    .font(.title3)
                    .padding()
                    .cardStyle(padding: 0)

                RavonPrimaryButton("Принять заказ") {
                    Task {
                        await vm.acceptOrder(orderId, estimatedPrepTime: estimatedMinutes)
                        showAcceptSheet = false
                    }
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Принять заказ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { showAcceptSheet = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var rejectSheet: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Причина отклонения")
                    .font(.headline)

                TextField("Например: закрыты, нет ингредиентов...", text: $rejectReason, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...6)

                RavonPrimaryButton("Отклонить заказ") {
                    Task {
                        await vm.rejectOrder(orderId, reason: rejectReason)
                        showRejectSheet = false
                        rejectReason = ""
                    }
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Отклонить заказ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { showRejectSheet = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var cancelSheet: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Причина отмены")
                    .font(.headline)

                TextField("Например: нет ингредиентов, слишком загружены...", text: $cancelReason, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...6)

                RavonPrimaryButton("Отменить заказ") {
                    Task {
                        await vm.cancelOrder(orderId, reason: cancelReason)
                        showCancelSheet = false
                        cancelReason = ""
                    }
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Отменить заказ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Назад") { showCancelSheet = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func statusColor(for status: OrderStatus) -> Color {
        switch status {
        case .created: return .orange
        case .accepted: return .blue
        case .preparing: return .purple
        case .ready: return .green
        case .cancelled, .cancelledByCustomer, .cancelledByRestaurant,
             .cancelledBySystem, .cancelledByCourier, .rejected:
            return .red
        default: return .gray
        }
    }
}
