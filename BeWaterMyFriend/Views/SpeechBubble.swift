import SwiftUI

/// What the drop says: a bubble with a small tail pointing at it, so the text
/// reads as the drop talking instead of a label next to it.
struct SpeechBubble: View {
    var text: String
    /// `.leading` (drop on the left), `.bottom` (drop below) or `.top` (drop above).
    var tailEdge: Edge = .leading
    /// For a bottom or top tail: x position of the tail inside the bubble (nil = centre).
    var tailX: CGFloat? = nil

    var body: some View {
        Text(text)
            .font(.footnote)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            // A bottom or top tail can point anywhere along the bubble, so it spans the width.
            .frame(maxWidth: tailEdge == .leading ? nil : .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .padding(tailEdge == .leading ? .leading : (tailEdge == .top ? .top : .bottom), BubbleShape.tail)
            .background(
                BubbleShape(tailEdge: tailEdge, tailX: tailX)
                    .fill(Dojo.card)
                    .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
            )
    }
}

nonisolated struct BubbleShape: Shape {
    static let tail: CGFloat = 7
    var tailEdge: Edge
    var tailX: CGFloat?

    func path(in rect: CGRect) -> Path {
        let t = Self.tail
        var box = rect
        switch tailEdge {
        case .leading:
            box.origin.x += t
            box.size.width -= t
        case .top:
            box.origin.y += t
            box.size.height -= t
        default:
            box.size.height -= t
        }
        var p = Path(roundedRect: box, cornerRadius: 12)
        if tailEdge == .leading {
            let y = min(box.midY, box.minY + 22)
            p.move(to: CGPoint(x: box.minX + 1, y: y - t))
            p.addLine(to: CGPoint(x: rect.minX, y: y))
            p.addLine(to: CGPoint(x: box.minX + 1, y: y + t))
        } else {
            let x = min(max(tailX ?? box.midX, box.minX + 16), box.maxX - 16)
            let (edge, tip) = tailEdge == .top ? (box.minY + 1, rect.minY) : (box.maxY - 1, rect.maxY)
            p.move(to: CGPoint(x: x - t, y: edge))
            p.addLine(to: CGPoint(x: x, y: tip))
            p.addLine(to: CGPoint(x: x + t, y: edge))
        }
        p.closeSubpath()
        return p
    }
}
