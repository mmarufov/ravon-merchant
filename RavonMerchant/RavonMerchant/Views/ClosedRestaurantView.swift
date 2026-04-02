import SwiftUI
import RavonCore

struct ClosedRestaurantView: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "storefront.circle")
                .font(.system(size: 80))
                .foregroundStyle(Color.ravonGray)

            Text("Ресторан закрыт")
                .font(.title.bold())

            Text("Ваш ресторан был закрыт навсегда.\nЭто действие необратимо.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()

            Button("Выйти", role: .destructive) {
                Task {
                    try? await AuthService.shared.signOut()
                }
            }
            .buttonStyle(.bordered)
            .padding(.bottom, 40)
        }
        .padding()
    }
}
