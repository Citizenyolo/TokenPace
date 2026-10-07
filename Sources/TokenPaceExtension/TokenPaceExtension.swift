import WidgetKit
import SwiftUI

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), data: QuotaData(
            geminiWeeklyRemaining: 0.8651, geminiWeeklyResetTime: "2026-10-01T15:10:55Z",
            gemini5hRemaining: 0.9199, gemini5hResetTime: "2026-09-30T18:09:47Z",
            claudeWeeklyRemaining: 0.7891, claudeWeeklyResetTime: "2026-10-01T15:10:13Z",
            claude5hRemaining: 1.0, claude5hResetTime: "2026-09-30T18:15:26Z"
        ))
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        let fileURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/quota.json")
        let entry = context.isPreview ? placeholder(in: context)
            : SimpleEntry(date: Date(), data: QuotaStore(fileURL: fileURL).read())
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        let fileURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/quota.json")
        let data = QuotaStore(fileURL: fileURL).read()
        let entries = QuotaPolicy.timelineDates(for: data, now: Date()).map {
            SimpleEntry(date: $0, data: data)
        }

        let timeline = Timeline(entries: entries, policy: .atEnd)
        completion(timeline)
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let data: QuotaData?
}

struct PacingIndicator: View {
    let isFresh: Bool
    let cachedPercentage: Double
    let resetTimeString: String
    let currentDate: Date
    let cycleDurationSeconds: TimeInterval
    
    var indicatorText: (String, Color)? {
        guard isFresh, let cycleEnd = QuotaPolicy.resetDate(resetTimeString) else { return nil }

        if currentDate >= cycleEnd {
            return nil // Data is stale; do not imply pacing from expired data
        }
        
        let cycleStart = cycleEnd.addingTimeInterval(-cycleDurationSeconds)
        let timeElapsed = currentDate.timeIntervalSince(cycleStart)
        
        let actualPct = cachedPercentage
        
        let idealPct: Double
        if timeElapsed >= cycleDurationSeconds || timeElapsed <= 0 {
            idealPct = 1.0
        } else {
            idealPct = 1.0 - (timeElapsed / cycleDurationSeconds)
        }
        
        let deviation = actualPct - idealPct
        let deviationInt = Int(round(deviation * 100))
        
        let color: Color
        if deviationInt > 2 {
            color = .green
        } else if deviationInt < -2 {
            color = .red
        } else {
            color = .blue
        }
        
        let sign = deviationInt > 0 ? "+" : ""
        return ("\(sign)\(deviationInt)%", color)
    }

    var body: some View {
        if let info = indicatorText {
            Text(info.0).foregroundColor(info.1).bold()
        } else {
            EmptyView()
        }
    }
}

struct TokenPaceEntryView : View {
    var entry: Provider.Entry
    
    // M1 Fix: strictly conservative reset text. Never fabricate availability.
    func formatRefreshText(from dateString: String, currentDate: Date) -> (String, Color) {
        guard let targetDate = QuotaPolicy.resetDate(dateString) else {
            return ("Unknown reset time", .secondary)
        }
        
        let timeInterval = targetDate.timeIntervalSince(currentDate)
        
        if timeInterval <= 0 {
            return ("Data stale", .secondary)
        }
        
        let totalHours = Int(timeInterval) / 3600
        let minutes = (Int(timeInterval) % 3600) / 60
        
        if totalHours >= 24 {
            let days = totalHours / 24
            let remainingHours = totalHours % 24
            let dayString = days == 1 ? "day" : "days"
            
            if remainingHours > 0 {
                return ("Resets in \(days) \(dayString) \(remainingHours)h \(minutes)m", .green)
            } else {
                return ("Resets in \(days) \(dayString) \(minutes)m", .green)
            }
        } else if totalHours > 0 {
            return ("Resets in \(totalHours)h \(minutes)m", .green)
        } else {
            return ("Resets in \(minutes)m", .green)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let d = entry.data, d.isValid(at: d.fetchedAt ?? entry.date) {
                let fresh = d.isFresh(at: entry.date)
                if !fresh { Text("Data stale — last known quota").foregroundColor(.secondary).bold() }
                VStack(alignment: .leading, spacing: 10) {
                    Text("GEMINI MODELS").bold()
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Five Hour Limit Remaining").bold()
                            Spacer()
                            PacingIndicator(isFresh: fresh, cachedPercentage: d.gemini5hRemaining, resetTimeString: d.gemini5hResetTime, currentDate: entry.date, cycleDurationSeconds: 5 * 3600)
                        }
                        HStack(spacing: 0) {
                            Text("  [")
                            QuotaBar(percentage: d.gemini5hRemaining)
                            Text("] ")
                            Text(String(format: "%.0f%%", d.gemini5hRemaining * 100)).foregroundColor(.primary).bold()
                        }
                        let refreshInfo = formatRefreshText(from: d.gemini5hResetTime, currentDate: entry.date)
                        Text(fresh ? "  " + refreshInfo.0 : "  Data stale").foregroundColor(fresh ? refreshInfo.1 : .secondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Weekly Limit Remaining").bold()
                            Spacer()
                            PacingIndicator(isFresh: fresh, cachedPercentage: d.geminiWeeklyRemaining, resetTimeString: d.geminiWeeklyResetTime, currentDate: entry.date, cycleDurationSeconds: 7 * 24 * 3600)
                        }
                        HStack(spacing: 0) {
                            Text("  [")
                            QuotaBar(percentage: d.geminiWeeklyRemaining)
                            Text("] ")
                            Text(String(format: "%.0f%%", d.geminiWeeklyRemaining * 100)).foregroundColor(.primary).bold()
                        }
                        let refreshInfo = formatRefreshText(from: d.geminiWeeklyResetTime, currentDate: entry.date)
                        Text(fresh ? "  " + refreshInfo.0 : "  Data stale").foregroundColor(fresh ? refreshInfo.1 : .secondary)
                    }
                }
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("CLAUDE AND GPT MODELS").bold()
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Five Hour Limit Remaining").bold()
                            Spacer()
                            PacingIndicator(isFresh: fresh, cachedPercentage: d.claude5hRemaining, resetTimeString: d.claude5hResetTime, currentDate: entry.date, cycleDurationSeconds: 5 * 3600)
                        }
                        HStack(spacing: 0) {
                            Text("  [")
                            QuotaBar(percentage: d.claude5hRemaining)
                            Text("] ")
                            Text(String(format: "%.0f%%", d.claude5hRemaining * 100)).foregroundColor(.primary).bold()
                        }
                        let refreshInfo = formatRefreshText(from: d.claude5hResetTime, currentDate: entry.date)
                        Text(fresh ? "  " + refreshInfo.0 : "  Data stale").foregroundColor(fresh ? refreshInfo.1 : .secondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Weekly Limit Remaining").bold()
                            Spacer()
                            PacingIndicator(isFresh: fresh, cachedPercentage: d.claudeWeeklyRemaining, resetTimeString: d.claudeWeeklyResetTime, currentDate: entry.date, cycleDurationSeconds: 7 * 24 * 3600)
                        }
                        HStack(spacing: 0) {
                            Text("  [")
                            QuotaBar(percentage: d.claudeWeeklyRemaining)
                            Text("] ")
                            Text(String(format: "%.0f%%", d.claudeWeeklyRemaining * 100)).foregroundColor(.primary).bold()
                        }
                        let refreshInfo = formatRefreshText(from: d.claudeWeeklyResetTime, currentDate: entry.date)
                        Text(fresh ? "  " + refreshInfo.0 : "  Data stale").foregroundColor(fresh ? refreshInfo.1 : .secondary)
                    }
                }
                // Embed the revision in the timeline itself, not just the installed bundle.
                // This makes an old WidgetKit snapshot distinguishable during acceptance.
                Text("Widget \(QuotaBuildIdentity.revision) · Data \(d.producerRevision ?? "legacy")")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
            } else {
                Text("Quota unavailable. Waiting for valid update...")
                Text("Widget \(QuotaBuildIdentity.revision)")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
            }
        }
        .font(.system(size: 14, weight: .regular, design: .monospaced))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
        .foregroundColor(.primary)
    }
}

@main
struct TokenPaceExtension: Widget {
    let kind: String = "TokenPaceExtension"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            TokenPaceEntryView(entry: entry)
                .containerBackground(Color(NSColor.windowBackgroundColor), for: .widget)
        }
        .configurationDisplayName("TokenPace")
        .description("Displays Agy CLI quota usage.")
        .supportedFamilies([.systemLarge])
    }
}

struct QuotaBar: View {
    let percentage: Double
    let totalBlocks = 25
    
    var body: some View {
        let filled = Int(round(percentage * Double(totalBlocks)))
        let empty = totalBlocks - filled
        let filledStr = String(repeating: "█", count: max(0, filled))
        let emptyStr = String(repeating: "░", count: max(0, empty))
        
        let barColor: Color = {
            if percentage >= 0.50 { return .green }
            else if percentage >= 0.25 { return .yellow }
            else { return .red }
        }()
        
        HStack(spacing: 0) {
            Text(filledStr).foregroundColor(barColor)
            Text(emptyStr).foregroundColor(.gray.opacity(0.5))
        }
    }
}
