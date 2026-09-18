import SwiftUI

/// Inline error display for use *inside* a sheet.
///
/// A sheet cannot rely on the alert attached to the screen behind it: SwiftUI will not
/// present an alert from a covered view, so an error raised while a sheet is up used to be
/// invisible even on the screens that did have an alert. A banner inside the sheet is also
/// better on a counter device — nothing to dismiss before retrying.
struct ErrorBanner: View {
    let message: String?
    var onDismiss: (() -> Void)?

    var body: some View {
        if let message {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let onDismiss {
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.1))
            .overlay(
                RoundedRectangle(cornerRadius: 10).stroke(Color.red.opacity(0.35), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .transition(.opacity)
        }
    }
}

extension View {
    /// Screen-level error alert. `suppressed` must be true whenever this screen has a sheet
    /// or covering presentation up — the sheet renders the same message inline with
    /// `ErrorBanner`, and presenting both at once is what makes SwiftUI complain about
    /// presenting over an existing presentation.
    func errorAlert(_ message: Binding<String?>, suppressed: Bool = false) -> some View {
        alert("Ошибка", isPresented: Binding(
            get: { message.wrappedValue != nil && !suppressed },
            set: { if !$0 { message.wrappedValue = nil } }
        )) {
            Button("OK") { message.wrappedValue = nil }
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}
