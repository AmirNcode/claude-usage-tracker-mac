import AppKit

/// Compact menu bar content: a progress icon on the left (outer ring = 5-hour
/// session, inner pie = weekly) and the two percentages stacked on the right
/// (session on top, weekly below).
///
/// Lives inside the status item's button and draws with the button's effective
/// appearance, so `labelColor` follows the menu bar's light/dark tint. It ignores
/// mouse events so clicks still reach the button and open the menu.
final class StatusBarView: NSView {
    struct Content {
        /// 0–100+ utilization, nil when there's no data yet.
        var session: Double?
        var weekly: Double?
        var sessionRingColor: NSColor = .labelColor
        var weeklyRingColor: NSColor = .labelColor
        var sessionTextColor: NSColor = .labelColor
        var weeklyTextColor: NSColor = .labelColor
    }

    var content = Content() {
        didSet { needsDisplay = true }
    }

    private let iconSize: CGFloat = 16
    private let ringWidth: CGFloat = 2
    private let spacing: CGFloat = 4
    private let padding: CGFloat = 4
    private let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold)

    /// Width of the text column, sized for the widest value ("100%") so the item
    /// doesn't jitter as numbers change.
    private var textWidth: CGFloat {
        ceil(("100%" as NSString).size(withAttributes: [.font: font]).width)
    }

    /// Total width the status item needs.
    var preferredWidth: CGFloat {
        padding + iconSize + spacing + textWidth + padding
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        // Resolve dynamic colors (labelColor) against the menu bar's appearance.
        effectiveAppearance.performAsCurrentDrawingAppearance {
            drawIcon()
            drawText()
        }
    }

    // MARK: - Icon

    private func drawIcon() {
        let center = NSPoint(x: padding + iconSize / 2, y: bounds.midY)

        // Outer ring: session.
        let ringRadius = (iconSize - ringWidth) / 2
        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: ringRadius, startAngle: 0, endAngle: 360)
        track.lineWidth = ringWidth
        content.sessionRingColor.withAlphaComponent(0.25).setStroke()
        track.stroke()

        let sessionFraction = fraction(content.session)
        if sessionFraction > 0 {
            let arc = NSBezierPath()
            arc.appendArc(withCenter: center, radius: ringRadius,
                          startAngle: 90, endAngle: 90 - 360 * sessionFraction, clockwise: true)
            arc.lineWidth = ringWidth
            arc.lineCapStyle = sessionFraction < 1 ? .round : .butt
            content.sessionRingColor.setStroke()
            arc.stroke()
        }

        // Inner pie: weekly.
        let pieRadius = ringRadius - ringWidth / 2 - 1.5
        let disc = NSBezierPath(ovalIn: NSRect(x: center.x - pieRadius, y: center.y - pieRadius,
                                               width: pieRadius * 2, height: pieRadius * 2))
        content.weeklyRingColor.withAlphaComponent(0.25).setFill()
        disc.fill()

        let weeklyFraction = fraction(content.weekly)
        if weeklyFraction >= 1 {
            content.weeklyRingColor.setFill()
            disc.fill()
        } else if weeklyFraction > 0 {
            let wedge = NSBezierPath()
            wedge.move(to: center)
            wedge.appendArc(withCenter: center, radius: pieRadius,
                            startAngle: 90, endAngle: 90 - 360 * weeklyFraction, clockwise: true)
            wedge.close()
            content.weeklyRingColor.setFill()
            wedge.fill()
        }
    }

    private func fraction(_ utilization: Double?) -> CGFloat {
        CGFloat(min(max((utilization ?? 0) / 100, 0), 1))
    }

    // MARK: - Text

    private func drawText() {
        let x = padding + iconSize + spacing
        let lineHeight = ceil(font.ascender - font.descender)
        // Two lines centered vertically, nudged together slightly to fit 22pt bars.
        let overlap: CGFloat = 1
        let top = bounds.midY + lineHeight - overlap / 2
        draw(percent(content.session), color: content.sessionTextColor,
             in: NSRect(x: x, y: top - lineHeight, width: textWidth, height: lineHeight))
        draw(percent(content.weekly), color: content.weeklyTextColor,
             in: NSRect(x: x, y: top - 2 * lineHeight + overlap, width: textWidth, height: lineHeight))
    }

    private func draw(_ text: String, color: NSColor, in rect: NSRect) {
        let style = NSMutableParagraphStyle()
        style.alignment = .right
        (text as NSString).draw(with: rect, options: [.usesLineFragmentOrigin], attributes: [
            .font: font, .foregroundColor: color, .paragraphStyle: style,
        ])
    }

    private func percent(_ utilization: Double?) -> String {
        guard let utilization else { return "–%" }
        return "\(Int(utilization.rounded()))%"
    }
}
