import SwiftUI
import RavonCore

struct LoginView: View {
    @StateObject private var vm = AuthViewModel()

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("Ravon")
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(Color.ravonRed)
            Text("Merchant")
                .font(.title2)
                .foregroundStyle(.secondary)

            Spacer()

            VStack(spacing: 16) {
                RavonTextField(
                    icon: "envelope",
                    placeholder: "Email",
                    text: $vm.email,
                    keyboardType: .emailAddress,
                    contentType: .emailAddress
                )
                RavonTextField(
                    icon: "lock",
                    placeholder: "Пароль",
                    text: $vm.password,
                    isSecure: true,
                    contentType: .password
                )
            }

            if let error = vm.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            RavonPrimaryButton("Войти", isLoading: vm.isLoading) {
                Task { await vm.signIn() }
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .background(Color.ravonGray.ignoresSafeArea())
    }
}
