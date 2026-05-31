import SwiftUI

struct CanvasBackground: View {
    var reducedDetail = false

    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = reducedDetail ? 48 : 24
            let minorColor = Color.secondary.opacity(reducedDetail ? 0.08 : 0.12)
            let majorColor = Color.secondary.opacity(reducedDetail ? 0.14 : 0.20)

            var x: CGFloat = 0
            var column = 0
            while x <= size.width {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                let isMajor = reducedDetail || column.isMultiple(of: 4)
                context.stroke(path, with: .color(isMajor ? majorColor : minorColor), lineWidth: 1)
                x += spacing
                column += 1
            }

            var y: CGFloat = 0
            var row = 0
            while y <= size.height {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                let isMajor = reducedDetail || row.isMultiple(of: 4)
                context.stroke(path, with: .color(isMajor ? majorColor : minorColor), lineWidth: 1)
                y += spacing
                row += 1
            }
        }
        .background(.background)
        .ignoresSafeArea()
    }
}
