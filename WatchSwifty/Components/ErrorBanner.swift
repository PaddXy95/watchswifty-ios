import SwiftUI
import WatchSwiftyCore

extension View {
    /// When a reload failed but older content is still shown: a banner on top, so the content is not taken as current.
    func staleBanner(_ error: UserFacingError?, retry: @escaping () async -> Void) -> some View {
        safeAreaInset(edge: .top) {
            if let error {
                HStack(spacing: 12) {
                    Image(systemName: error.kind == .offline ? "wifi.slash" : "exclamationmark.triangle")
                    Text(error.kind == .offline ? "Server nicht erreichbar – Stand von vorhin." : error.message)
                        .font(.footnote)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Erneut versuchen") { Task { await retry() } }
                        .font(.footnote.bold())
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
            }
        }
    }
}
