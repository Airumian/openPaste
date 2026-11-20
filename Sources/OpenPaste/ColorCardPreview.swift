import SwiftUI

struct ColorCardPreview: View {
    let value: String
    let usesDarkText: Bool
    let index: Int
    @ScaledMetric(relativeTo: .title2) private var fontSize = 20

    var body: some View {
        Text(ClipboardColor.displayValue(value))
            .font(.system(size: fontSize, weight: .semibold, design: .monospaced))
            .multilineTextAlignment(.center)
            .lineLimit(4)
            .minimumScaleFactor(0.6)
            .foregroundStyle(usesDarkText ? Color.black : .white)
            .padding(.horizontal, 20)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottomTrailing) {
                HStack(spacing: 4) {
                    Image(systemName: "text.alignleft").font(.system(size: 10))
                    Text("\(index)").monospacedDigit()
                }
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.75))
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(.black.opacity(0.3), in: Capsule())
                .padding(8)
            }
    }
}
