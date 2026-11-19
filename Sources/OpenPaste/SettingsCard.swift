import SwiftUI

struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(.horizontal, SettingsLayout.cardInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .quaternaryLabelColor).opacity(0.35),
                    in: .rect(cornerRadius: 12))
    }
}
