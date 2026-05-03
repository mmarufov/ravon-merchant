import SwiftUI
import RavonCore

struct RestaurantHoursView: View {
    @ObservedObject var vm: SettingsViewModel
    @State private var entries: [DayEntry] = []
    @State private var didLoad = false

    struct DayEntry: Identifiable {
        let dayOfWeek: Int
        var openingTime: Date
        var closingTime: Date
        var isClosed: Bool

        var id: Int { dayOfWeek }

        var dayName: String {
            switch dayOfWeek {
            case 0: return "Воскресенье"
            case 1: return "Понедельник"
            case 2: return "Вторник"
            case 3: return "Среда"
            case 4: return "Четверг"
            case 5: return "Пятница"
            case 6: return "Суббота"
            default: return ""
            }
        }
    }

    var body: some View {
        Form {
            Section {
                Label("Время указывается по Душанбе (UTC+5).", systemImage: "globe")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ForEach($entries) { $entry in
                Section(entry.dayName) {
                    Toggle("Закрыто", isOn: $entry.isClosed)

                    if !entry.isClosed {
                        DatePicker("Открытие", selection: $entry.openingTime, displayedComponents: .hourAndMinute)
                        DatePicker("Закрытие", selection: $entry.closingTime, displayedComponents: .hourAndMinute)
                    }
                }
            }

            Section {
                RavonPrimaryButton("Сохранить", isLoading: vm.isSaving) {
                    Task { await save() }
                }
            }
        }
        .navigationTitle("Часы работы")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if !didLoad {
                loadEntries()
                didLoad = true
            }
        }
    }

    private func loadEntries() {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"

        let defaultOpen = formatter.date(from: "09:00:00") ?? Date()
        let defaultClose = formatter.date(from: "22:00:00") ?? Date()

        // Monday–Saturday, then Sunday (1-6, 0)
        let dayOrder = [1, 2, 3, 4, 5, 6, 0]
        entries = dayOrder.map { day in
            if let existing = vm.hours.first(where: { $0.dayOfWeek == day }) {
                return DayEntry(
                    dayOfWeek: day,
                    openingTime: formatter.date(from: existing.openingTime) ?? defaultOpen,
                    closingTime: formatter.date(from: existing.closingTime) ?? defaultClose,
                    isClosed: existing.isClosed
                )
            } else {
                return DayEntry(
                    dayOfWeek: day,
                    openingTime: defaultOpen,
                    closingTime: defaultClose,
                    isClosed: false
                )
            }
        }
    }

    private func save() async {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"

        let upserts = entries.map { entry in
            RestaurantHoursUpsert(
                restaurantId: vm.restaurantId,
                dayOfWeek: entry.dayOfWeek,
                openingTime: formatter.string(from: entry.openingTime),
                closingTime: formatter.string(from: entry.closingTime),
                isClosed: entry.isClosed
            )
        }

        await vm.saveHours(upserts)
    }
}
