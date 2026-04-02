import SwiftUI
import Combine
import RavonCore

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var email = ""
    @Published var password = ""
    @Published var fullName = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isSignUpMode = false

    func signIn() async {
        guard !email.isEmpty, !password.isEmpty else {
            errorMessage = "Введите email и пароль"
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            try await AuthService.shared.signIn(email: email, password: password)

            if AuthService.shared.userRole != .merchant {
                try await AuthService.shared.signOut()
                errorMessage = "Доступ только для мерчантов"
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func signUp() async {
        guard !email.isEmpty, !password.isEmpty else {
            errorMessage = "Введите email и пароль"
            return
        }
        guard !fullName.isEmpty else {
            errorMessage = "Введите ваше имя"
            return
        }
        guard password.count >= 6 else {
            errorMessage = "Пароль должен быть не менее 6 символов"
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            try await AuthService.shared.signUp(
                email: email,
                password: password,
                fullName: fullName,
                role: .merchant
            )
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}
