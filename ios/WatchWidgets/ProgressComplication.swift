import BrushCore
import SwiftUI
import WidgetKit

@main
struct FogmosasWatchWidgets: WidgetBundle {
    init() { I18n.setLanguage(nil) }
    var body: some Widget { ProgressComplication() }
}

struct SummaryEntry: TimelineEntry {
    let date: Date
    let summary: WatchSummaryData?
}

struct SummaryProvider: TimelineProvider {
    func placeholder(in context: Context) -> SummaryEntry {
        SummaryEntry(date: Date(), summary: WatchSummaryData(day: Date(), todayCount: 1, perDay: 2, streak: 5, lastDurationS: 125))
    }

    func getSnapshot(in context: Context, completion: @escaping (SummaryEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entry(at: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SummaryEntry>) -> Void) {
        let now = Date()
        let midnight = Calendar.current.startOfDay(for: now.addingTimeInterval(86400))
        // Refresh at midnight (the count goes back to 0); the app reloads after every brushing.
        completion(Timeline(entries: [entry(at: now), entry(at: midnight)], policy: .after(midnight)))
    }

    private func entry(at d: Date) -> SummaryEntry {
        SummaryEntry(date: d, summary: WatchSummaryStore.load()?.asOf(d))
    }
}

private let brand = Color(red: 0.341, green: 0.773, blue: 0.714)

struct ComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SummaryEntry

    var body: some View {
        let s = entry.summary
        let count = s?.todayCount ?? 0
        let perDay = max(s?.perDay ?? 2, 1)
        let fraction = min(Double(count) / Double(perDay), 1)
        switch family {
        case .accessoryCircular:
            Gauge(value: fraction) { Text("🪥") } currentValueLabel: { Text("\(count)/\(perDay)") }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(brand)
        case .accessoryCorner:
            Text("🪥")
                .widgetLabel { Gauge(value: fraction) { Text("") } currentValueLabel: { Text("\(count)/\(perDay)") }.tint(brand) }
        case .accessoryInline:
            Text("🪥 \(count)/\(perDay) · 🔥 \(s?.streak ?? 0)")
        default:
            VStack(alignment: .leading, spacing: 2) {
                Text(tr("🪥 Fogmosás")).font(.headline).widgetAccentable()
                Text(tr("Ma {0}/{1} · 🔥 {2} nap", count, perDay, s?.streak ?? 0)).font(.caption)
                Gauge(value: fraction) { EmptyView() }.gaugeStyle(.accessoryLinearCapacity).tint(brand)
            }
        }
    }
}

struct ProgressComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FogmosasProgress", provider: SummaryProvider()) { entry in
            ComplicationView(entry: entry).containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("DentHub-Brush")
        .description(tr("A mai fogmosások és a sorozat."))
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}
