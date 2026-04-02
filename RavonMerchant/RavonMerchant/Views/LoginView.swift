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
                if vm.isSignUpMode {
                    RavonTextField(
                        icon: "person",
                        placeholder: "Имя",
                        text: $vm.fullName,
                        contentType: .name
                    )
                }
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
                    contentType: vm.isSignUpMode ? .newPassword : .password
                )
            }

            if let error = vm.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            RavonPrimaryButton(vm.isSignUpMode ? "Создать аккаунт" : "Войти", isLoading: vm.isLoading) {
                Task {
                    if vm.isSignUpMode {
                        await vm.signUp()
                    } else {
                        await vm.signIn()
                    }
                }
            }

            Button {
                vm.errorMessage = nil
                vm.isSignUpMode.toggle()
            } label: {
                Text(vm.isSignUpMode ? "Уже есть аккаунт? Войти" : "Нет аккаунта? Создать")
                    .font(.subheadline)
                    .foregroundStyle(Color.ravonRed)
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .background(Color.ravonGray.ignoresSafeArea())
    }
}
