import BrushCore
import SwiftUI

enum Theme {
    static let brand = Color(red: 0.118, green: 0.608, blue: 0.722)    // #1e9bb8
    static let brand2 = Color(red: 0.341, green: 0.773, blue: 0.714)   // #57c5b6
    static let warn = Color(red: 0.910, green: 0.514, blue: 0.227)     // #e8833a
    static let danger = Color(red: 0.851, green: 0.325, blue: 0.310)   // #d9534f
    static let ok = Color(red: 0.180, green: 0.620, blue: 0.416)       // #2e9e6a
    static let kidTop = Color(red: 1.0, green: 0.965, blue: 0.839)
    static let kidBottom = Color(red: 1.0, green: 0.890, blue: 0.925)
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 6) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemGroupedBackground)))
    }
}

struct AvatarCircle: View {
    let emoji: String
    var size: CGFloat = 54
    var selected = false
    var body: some View {
        Text(emoji)
            .font(.system(size: size * 0.56))
            .frame(width: size, height: size)
            .background(Circle().fill(Color(.systemBackground)))
            .overlay(Circle().stroke(selected ? Theme.brand : Color.clear, lineWidth: 3))
            .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
    }
}

struct ProgressRing: View {
    let fraction: Double
    let label: String
    let sublabel: String
    var color: Color = Theme.brand
    var size: CGFloat = 220
    var body: some View {
        ZStack {
            Circle().stroke(Color(.systemGray5), lineWidth: size * 0.09)
            Circle()
                .trim(from: 0, to: max(0.001, min(fraction, 1)))
                .stroke(color, style: StrokeStyle(lineWidth: size * 0.09, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.4), value: fraction)
            VStack(spacing: 2) {
                Text(label).font(.system(size: size * 0.2, weight: .heavy, design: .rounded)).monospacedDigit()
                Text(sublabel).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }
}

struct QuadrantGrid: View {
    let current: Int  // 1...4
    var labels = true
    var body: some View {
        LazyVGrid(columns: [GridItem(.fixed(70)), GridItem(.fixed(70))], spacing: 6) {
            ForEach(0..<4, id: \.self) { i in
                let state: Color = i + 1 < current ? Theme.brand2 : (i + 1 == current ? Theme.brand : Color(.systemGray5))
                RoundedRectangle(cornerRadius: 8).fill(state)
                    .frame(height: 30)
                    .overlay(Text(labels ? Quadrant.names[i] : "").font(.caption2.bold())
                        .foregroundStyle(i + 1 <= current ? .white : .secondary))
            }
        }
        .frame(width: 150)
    }
}

struct Banner: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14).fill(color.opacity(0.12)))
    }
}

struct BigButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.title3.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .foregroundStyle(.white)
                .background(RoundedRectangle(cornerRadius: 22)
                    .fill(LinearGradient(colors: [Theme.brand, Theme.brand2], startPoint: .topLeading, endPoint: .bottomTrailing)))
        }
        .buttonStyle(.plain)
    }
}

extension Binding where Value == Date {
    /// Edit a ClockTime with a DatePicker.
    init(clock: Binding<ClockTime>) {
        self.init(get: {
            Calendar.current.date(bySettingHour: clock.wrappedValue.hour, minute: clock.wrappedValue.minute, second: 0, of: Date()) ?? Date()
        }, set: { d in
            let c = Calendar.current.dateComponents([.hour, .minute], from: d)
            clock.wrappedValue = ClockTime(c.hour ?? 0, c.minute ?? 0)
        })
    }
}
