import SwiftUI

/// Standard X dismiss button used across all sheets and modals.
struct XDismissButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.body.bold())
                .foregroundColor(.primary)
        }
    }
}
