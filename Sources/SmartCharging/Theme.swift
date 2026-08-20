import SwiftUI

/// Instrument-panel palette, shared with the web guide in docs/.
/// Deep teal accent; good / marginal / bad kept separate from it so
/// state never reads as decoration.
enum Theme {

    static let accent = Color(light: .init(red: 0.04, green: 0.43, blue: 0.50),
                              dark:  .init(red: 0.31, green: 0.76, blue: 0.85))

    static let pass   = Color(light: .init(red: 0.11, green: 0.50, blue: 0.29),
                              dark:  .init(red: 0.32, green: 0.79, blue: 0.54))

    static let warn   = Color(light: .init(red: 0.66, green: 0.42, blue: 0.00),
                              dark:  .init(red: 0.88, green: 0.65, blue: 0.29))

    static let fail   = Color(light: .init(red: 0.70, green: 0.15, blue: 0.12),
                              dark:  .init(red: 0.94, green: 0.47, blue: 0.44))

    static let muted  = Color(light: .init(red: 0.35, green: 0.39, blue: 0.38),
                              dark:  .init(red: 0.59, green: 0.64, blue: 0.62))

    static let hairline = Color(light: .init(red: 0.78, green: 0.81, blue: 0.80),
                                dark:  .init(red: 0.18, green: 0.22, blue: 0.21))

    static let plate = Color(light: .init(red: 0.96, green: 0.97, blue: 0.97),
                             dark:  .init(red: 0.09, green: 0.11, blue: 0.11))

    /// Tabular figures, so numbers don't jitter as they update.
    static func readout(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
            .monospacedDigit()
    }

    static func label(_ size: CGFloat = 10) -> Font {
        .system(size: size, weight: .semibold, design: .monospaced)
    }
}

extension Color {
    /// Resolves per appearance so both themes get deliberate values
    /// rather than one being a naive inversion of the other.
    init(light: NSColor, dark: NSColor) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark ? dark : light
        })
    }
}

private extension NSColor {
    convenience init(red: CGFloat, green: CGFloat, blue: CGFloat) {
        self.init(srgbRed: red, green: green, blue: blue, alpha: 1)
    }
}

// MARK: - Small shared pieces

/// Uppercase spec-plate caption.
struct FieldLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(Theme.label())
            .tracking(1.4)
            .foregroundStyle(Theme.muted)
    }
}

/// A labelled number with its unit, aligned for scanning in a column.
struct Readout: View {
    let label: String
    let value: String
    let unit: String
    var tint: Color = .primary
    var size: CGFloat = 22

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            FieldLabel(label)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(Theme.readout(size))
                    .foregroundStyle(tint)
                Text(unit)
                    .font(.system(size: size * 0.45, weight: .regular, design: .monospaced))
                    .foregroundStyle(Theme.muted)
            }
        }
    }
}

/// Battery-flow history. An area under the line, a zero rule, and an
/// emphasized endpoint — the last value is the one being read.
struct FlowSparkline: View {
    let values: [Double]
    var height: CGFloat = 44

    /// Map sample `i` into the plot area. Kept off the ViewBuilder so the
    /// result builder doesn't try to treat it as a view.
    private func point(_ i: Int, width w: CGFloat, mid: CGFloat, maxAbs: Double) -> CGPoint {
        let x = values.count <= 1 ? 0 : w * CGFloat(i) / CGFloat(values.count - 1)
        let y = mid - CGFloat(values[i] / maxAbs) * (mid - 2)
        return CGPoint(x: x, y: y)
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let maxAbs = max(values.map { abs($0) }.max() ?? 1, 5)
            let mid = h / 2

            ZStack {
                // zero line — the only threshold that matters
                Path { p in
                    p.move(to: CGPoint(x: 0, y: mid))
                    p.addLine(to: CGPoint(x: w, y: mid))
                }
                .stroke(Theme.hairline, style: .init(lineWidth: 1, dash: [2, 3]))

                if values.count > 1 {
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: mid))
                        for i in values.indices {
                            p.addLine(to: point(i, width: w, mid: mid, maxAbs: maxAbs))
                        }
                        p.addLine(to: CGPoint(x: w, y: mid))
                        p.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [Theme.accent.opacity(0.28), Theme.accent.opacity(0.02)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )

                    Path { p in
                        p.move(to: point(0, width: w, mid: mid, maxAbs: maxAbs))
                        for i in values.indices.dropFirst() {
                            p.addLine(to: point(i, width: w, mid: mid, maxAbs: maxAbs))
                        }
                    }
                    .stroke(Theme.accent, style: .init(lineWidth: 1.5, lineJoin: .round))

                    let last = point(values.count - 1, width: w, mid: mid, maxAbs: maxAbs)
                    Circle()
                        .fill(values.last! < 0 ? Theme.fail : Theme.pass)
                        .frame(width: 6, height: 6)
                        .position(last)
                }
            }
        }
        .frame(height: height)
    }
}
