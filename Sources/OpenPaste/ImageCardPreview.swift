import SwiftUI

struct ImageCardPreview: View {
    let image: NSImage?
    let pixelSize: CGSize?
    let index: Int

    var body: some View {
        // A fixed layout proposal keeps the image's aspect ratio from resizing the card's header.
        GeometryReader { area in
            ZStack {
                Canvas { context, size in
                    let tile: CGFloat = 8
                    context.fill(
                        Path(CGRect(origin: .zero, size: size)),
                        with: .color(Color(nsColor: .textBackgroundColor)))
                    var squares = Path()
                    for row in 0..<Int(ceil(size.height / tile)) {
                        for column in 0..<Int(ceil(size.width / tile))
                        where (row + column).isMultiple(of: 2) {
                            squares.addRect(
                                CGRect(
                                    x: CGFloat(column) * tile, y: CGFloat(row) * tile,
                                    width: tile, height: tile))
                        }
                    }
                    context.fill(squares, with: .color(Color.primary.opacity(0.06)))
                }
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: area.size.width, height: area.size.height)
                }
            }
            .frame(width: area.size.width, height: area.size.height)
            .clipped()
        }
        .overlay(alignment: .bottom) {
            ZStack {
                if let pixelSize {
                    Text("\(Int(pixelSize.width)) × \(Int(pixelSize.height))")
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(.regularMaterial, in: Capsule())
                }
                HStack {
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "text.alignleft").font(.system(size: 10))
                        Text("\(index)").monospacedDigit()
                    }
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.regularMaterial, in: Capsule())
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(8)
        }
    }
}
