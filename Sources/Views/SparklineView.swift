import SwiftUI

public struct SparklineView: View {
    public let data: [Double]
    public let minVal: Double
    public let maxVal: Double
    public let strokeColor: Color
    public let fillColor: Color
    
    public init(
        data: [Double],
        minVal: Double = 0.0,
        maxVal: Double = 100.0,
        strokeColor: Color = .blue,
        fillColor: Color = .blue.opacity(0.15)
    ) {
        self.data = data
        self.minVal = minVal
        self.maxVal = maxVal
        self.strokeColor = strokeColor
        self.fillColor = fillColor
    }
    
    public var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let count = max(data.count, 2)
            let stepX = w / CGFloat(count - 1)
            let range = max(maxVal - minVal, 1.0)
            
            let points = data.enumerated().map { index, val in
                let clamped = min(maxVal, max(minVal, val))
                let normalized = (clamped - minVal) / range
                let x = CGFloat(index) * stepX
                let y = h - (CGFloat(normalized) * h)
                return CGPoint(x: x, y: y)
            }
            
            ZStack {
                // Gradient Fill Path
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: CGPoint(x: 0, y: h))
                    path.addLine(to: first)
                    for pt in points.dropFirst() {
                        path.addLine(to: pt)
                    }
                    if let last = points.last {
                        path.addLine(to: CGPoint(x: last.x, y: h))
                    }
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [fillColor, fillColor.opacity(0.01)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                
                // Stroke Line Path
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    for pt in points.dropFirst() {
                        path.addLine(to: pt)
                    }
                }
                .stroke(
                    strokeColor,
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                )
            }
        }
    }
}
