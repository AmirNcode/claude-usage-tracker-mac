import SwiftUI
import Charts
import UsageCore

struct StatsView: View {
    @ObservedObject var store: UsageHistoryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if store.samples.count < 2 {
                emptyState
            } else {
                chart
                Divider()
                timeline
            }
        }
        .frame(width: 520, height: 460)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.xyaxis.line").font(.largeTitle).foregroundStyle(.secondary)
            Text("Collecting data…").font(.headline)
            Text("Usage is recorded each time the app refreshes. Check back after a few cycles — keep this window open to sample faster.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Chart

    private struct Plot: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
        let series: String
    }

    private var plotData: [Plot] {
        store.samples.flatMap { s -> [Plot] in
            var points: [Plot] = []
            if let v = s.session { points.append(Plot(date: s.date, value: v, series: "Session")) }
            if let v = s.weekly { points.append(Plot(date: s.date, value: v, series: "Weekly")) }
            return points
        }
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Usage over time").font(.headline)
            Chart(plotData) { p in
                LineMark(
                    x: .value("Time", p.date),
                    y: .value("Used %", p.value)
                )
                .foregroundStyle(by: .value("Window", p.series))
                .interpolationMethod(.monotone)
            }
            .chartYScale(domain: 0...100)
            .chartForegroundStyleScale(["Session": Color.accentColor, "Weekly": Color.orange])
            .chartYAxis { AxisMarks(values: [0, 25, 50, 75, 100]) }
            .frame(height: 200)
        }
        .padding()
    }

    // MARK: - Timeline

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Timeline").font(.headline).padding(.horizontal).padding(.top, 8)
            List(timelineRows) { row in
                HStack(spacing: 12) {
                    Text(row.time).font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary).frame(width: 84, alignment: .leading)
                    metric("Session", row.session, row.sessionDelta)
                    Divider().frame(height: 14)
                    metric("Weekly", row.weekly, row.weeklyDelta)
                    Spacer()
                }
                .listRowSeparator(.visible)
            }
            .listStyle(.plain)
        }
    }

    private func metric(_ label: String, _ pct: String, _ delta: DeltaText) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(pct).font(.body.monospacedDigit())
            if let text = delta.text {
                Text(text).font(.caption.monospacedDigit()).foregroundStyle(delta.color)
            }
        }
    }

    // Most-recent-first rows for display.
    private var timelineRows: [Row] {
        UsageHistory.timeline(store.samples).reversed().map(Row.init)
    }

    private struct DeltaText { let text: String?; let color: Color }

    private struct Row: Identifiable {
        let id = UUID()
        let time: String
        let session: String
        let weekly: String
        let sessionDelta: DeltaText
        let weeklyDelta: DeltaText

        init(_ e: TimelineEntry) {
            let f = DateFormatter()
            f.dateFormat = "MMM d HH:mm"
            time = f.string(from: e.date)
            session = Row.pct(e.session)
            weekly = Row.pct(e.weekly)
            sessionDelta = Row.delta(e.sessionDelta)
            weeklyDelta = Row.delta(e.weeklyDelta)
        }

        static func pct(_ v: Double?) -> String {
            guard let v else { return "–" }
            return "\(Int(v.rounded()))%"
        }

        static func delta(_ v: Double?) -> DeltaText {
            guard let v else { return DeltaText(text: nil, color: .secondary) }
            let rounded = Int(v.rounded())
            if rounded == 0 { return DeltaText(text: "±0", color: .secondary) }
            let sign = rounded > 0 ? "+" : ""
            // Increase = spending (orange), decrease = a reset (green).
            return DeltaText(text: "\(sign)\(rounded)", color: rounded > 0 ? .orange : .green)
        }
    }
}
