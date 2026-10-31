import SwiftUI

public struct AppLogoBadgeView: View {
    public let size: CGFloat
    public var showGlow: Bool = true
    
    public init(size: CGFloat = 36, showGlow: Bool = true) {
        self.size = size
        self.showGlow = showGlow
    }
    
    public var body: some View {
        ZStack {
            // Ambient outer glow
            if showGlow {
                RoundedRectangle(cornerRadius: size * 0.26)
                    .fill(
                        LinearGradient(
                            colors: [Color.cyan.opacity(0.35), Color.blue.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size + 4, height: size + 4)
                    .blur(radius: 3)
            }
            
            // Base Squircle Background
            RoundedRectangle(cornerRadius: size * 0.24)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.10, green: 0.13, blue: 0.20),
                            Color(red: 0.05, green: 0.07, blue: 0.12)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.24)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.25),
                                    Color.cyan.opacity(0.3),
                                    Color.white.opacity(0.05)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
            
            // Central Chip Icon with Gradient
            Image(systemName: "cpu")
                .resizable()
                .scaledToFit()
                .frame(width: size * 0.52, height: size * 0.52)
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 0.35, green: 0.85, blue: 1.0),
                            Color(red: 0.2, green: 0.55, blue: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            // Inner Core Accent Dot
            Circle()
                .fill(Color.cyan)
                .frame(width: size * 0.12, height: size * 0.12)
                .shadow(color: .cyan, radius: 2)
        }
    }
}
