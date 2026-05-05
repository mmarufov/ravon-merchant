import SwiftUI
import RavonCore

struct ChangePasswordScreen: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = AuthFlowViewModel(role: .merchant)

    var body: some View {
        RavonNewPasswordView(vm: vm, mode: .changeFromSettings) {
            dismiss()
        }
    }
}
