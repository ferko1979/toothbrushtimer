import BrushCore
import SwiftUI

struct StatsView: View {
    @EnvironmentObject var model: AppModel

    private var profile: Profile { model.activeProfile }
    private var records: [BrushRecord] { model.records(for: profile.id) }

    var body: some View {
        NavigationStack {
            List {
                Section("Ez a hét") {
                    Text(model.coach.weeklyProgress(records, goals: profile.goals, today: Date())).font(.subheadline)
                    WeekBars(records: records, target: profile.goals.targetS)
                        .frame(height: 120)
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                }
                if model.settings.isOn("monthly_report") {
                    let c = Calendar.current.dateComponents([.year, .month], from: Date())
                    let rep = monthlyReport(records, goals: profile.goals, year: c.year ?? 2026, month: c.month ?? 1,
                                            locale: model.settings.waterLocale)
                    let text = formatMonthly(rep, goals: profile.goals, name: profile.name)
                    Section("Havi összefoglaló") {
                        Text(text).font(.footnote)
                        ShareLink(item: text) { Label("Megosztás (pl. a fogorvosnak)", systemImage: "square.and.arrow.up") }
                        ShareLink(item: recordsCSV(records)) { Label("Exportálás CSV-ként", systemImage: "tablecells") }
                    }
                }
                Section("Legutóbbiak") {
                    if records.isEmpty { Text("Még nincs mért fogmosás.").foregroundStyle(.secondary) }
                    ForEach(records.sorted { $0.start > $1.start }.prefix(30)) { r in
                        HStack {
                            Text(r.start.formatted(date: .abbreviated, time: .shortened))
                            Spacer()
                            if !r.tapOff { Text("🚰").accessibilityLabel("folyt a csap") }
                            if r.source == "watch" { Image(systemName: "applewatch") }
                            Text(formatClock(r.durationS)).monospacedDigit()
                                .foregroundStyle(r.durationS >= profile.goals.targetS ? Theme.ok : Theme.warn)
                        }
                    }
                }
            }
            .navigationTitle("Statisztika")
        }
    }
}

private struct WeekBars: View {
    let records: [BrushRecord]
    let target: Double

    var body: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let days: [Date] = (0..<7).reversed().map { cal.date(byAdding: .day, value: -$0, to: today)! }
        let avgs: [Double] = days.map { d in
            let rs = records.filter { cal.isDate($0.start, inSameDayAs: d) }
            return rs.isEmpty ? 0 : rs.map(\.durationS).reduce(0, +) / Double(rs.count)
        }
        let maxV = max(target * 1.2, avgs.max() ?? 0)
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(0..<7, id: \.self) { i in
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(avgs[i] >= target ? Theme.brand : (avgs[i] > 0 ? Theme.warn : Color(.systemGray5)))
                        .frame(height: max(4, 90 * avgs[i] / maxV))
                    Text(days[i].formatted(.dateTime.weekday(.narrow))).font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}
