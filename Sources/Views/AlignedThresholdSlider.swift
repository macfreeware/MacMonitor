import SwiftUI

public struct AlignedThresholdSlider: View {
    @Binding public var value: Double
    public let range: ClosedRange<Double>
    public let step: Double
    public let presets: [Double]
    public let accentColor: Color
    @ObservedObject private var settings: AppSettings = AppSettings.shared
    
    public init(
        value: Binding<Double>,
        range: ClosedRange<Double> = 20...95,
        step: Double = 5,
        presets: [Double] = [30, 50, 70, 80, 90],
        accentColor: Color = .blue
    ) {
        self._value = value
        self.range = range
        self.step = step
        self.presets = presets
        self.accentColor = accentColor
    }
    
    public var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let thumbRadius: CGFloat = 8
            let trackWidth = max(10, w - thumbRadius * 2)
            let span = max(1.0, range.upperBound - range.lowerBound)
            let progress = CGFloat(min(1.0, max(0.0, (value - range.lowerBound) / span)))
            let thumbX = thumbRadius + trackWidth * progress
            
            VStack(spacing: 4) {
                // Track with Ticks & Thumb
                ZStack(alignment: .leading) {
                    // Background track
                    Capsule()
                        .fill(Color.primary.opacity(0.12))
                        .frame(height: 5)
                    
                    // Active filled track
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [accentColor.opacity(0.7), accentColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(0, thumbX), height: 5)
                    
                    // Small tick dots at exact preset positions along the track
                    ForEach(presets, id: \.self) { preset in
                        let presetProgress = CGFloat((preset - range.lowerBound) / span)
                        let tickX = thumbRadius + trackWidth * presetProgress
                        
                        Circle()
                            .fill(preset <= value ? Color.white.opacity(0.7) : Color.primary.opacity(0.25))
                            .frame(width: 3, height: 3)
                            .position(x: tickX, y: thumbRadius)
                    }
                    
                    // Thumb
                    Circle()
                        .fill(Color.white)
                        .frame(width: thumbRadius * 2, height: thumbRadius * 2)
                        .shadow(color: Color.black.opacity(0.3), radius: 2.5, y: 1)
                        .overlay(
                            Circle()
                                .stroke(accentColor.opacity(0.6), lineWidth: 1.5)
                        )
                        .offset(x: thumbX - thumbRadius)
                }
                .frame(height: thumbRadius * 2)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            let locX = min(max(gesture.location.x - thumbRadius, 0), trackWidth)
                            let pct = locX / trackWidth
                            let rawVal = range.lowerBound + Double(pct) * span
                            let stepped = round(rawVal / step) * step
                            value = min(range.upperBound, max(range.lowerBound, stepped))
                        }
                )
                
                // Perfectly Aligned Preset Labels Directly Under Ticks
                ZStack {
                    ForEach(presets, id: \.self) { preset in
                        let presetProgress = CGFloat((preset - range.lowerBound) / span)
                        let labelX = thumbRadius + trackWidth * presetProgress
                        let isSelected = Int(value) == Int(preset)
                        
                        Button(action: {
                            value = preset
                        }) {
                            Text(settings.isTurkish ? "%\(Int(preset))" : "\(Int(preset))%")
                                .font(.system(size: 8.5, weight: isSelected ? .bold : .medium, design: .rounded))
                                .foregroundColor(isSelected ? accentColor : .secondary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1.5)
                                .background(isSelected ? accentColor.opacity(0.15) : Color.clear)
                                .cornerRadius(3)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .position(x: labelX, y: 8)
                    }
                }
                .frame(height: 16)
            }
        }
        .frame(height: 42)
    }
}
