import SwiftUI

/// Transient error banner for failed container actions
struct ActionErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.white)

            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.white)
                .lineLimit(2)

            Spacer()

            Button {
                withAnimation(.easeOut(duration: 0.3)) {
                    onDismiss()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.85))
    }
}
