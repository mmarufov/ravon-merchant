import SwiftUI
import RavonCore

struct AcceptingOrdersSheet: View {
    let isCurrentlyAccepting: Bool
    let acceptingOrdersUntil: Date?
    let isBusy: Bool
    let onPickPreset: (TimeInterval?) -> Void
    let onResume: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if isCurrentlyAccepting {
                    pauseHeader
                    presetGrid
                } else {
                    resumeHeader
                    RavonPrimaryButton("Снова принимать заказы", isLoading: isBusy) {
                        onResume()
                        dismiss()
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle(isCurrentlyAccepting ? "Не принимать заказы" : "Не принимаете")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Headers

    private var pauseHeader: some View {
        VStack(spacing: 6) {
            Text("Когда снова начнёте принимать заказы?")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("Через выбранное время мы автоматически вернёмся в работу. \"До отмены\" — оставит ресторан выключенным до вашего возврата.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var resumeHeader: some View {
        VStack(spacing: 6) {
            Text("Сейчас вы не принимаете заказы")
                .font(.headline)
            if let until = acceptingOrdersUntil {
                Text("Автоматически вернёмся к работе в \(formatUntil(until))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Пауза до отмены — клиенты видят вас, но не могут оформить заказ")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Preset grid

    private var presetGrid: some View {
        VStack(spacing: 12) {
            chip(title: "15 минут", subtitle: "Короткий перерыв", interval: 15 * 60)
            chip(title: "30 минут", subtitle: "Перерыв на обед", interval: 30 * 60)
            chip(title: "1 час",    subtitle: "Длинная пауза", interval: 60 * 60)
            chip(title: "До отмены", subtitle: "Без авто-возврата", interval: nil)
        }
    }

    private func chip(title: String, subtitle: String, interval: TimeInterval?) -> some View {
        Button {
            onPickPreset(interval)
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.semibold))
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if interval != nil {
                    Image(systemName: "clock")
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "infinity")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
            )
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
    }

    private func formatUntil(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "Asia/Dushanbe") ?? .current
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}
