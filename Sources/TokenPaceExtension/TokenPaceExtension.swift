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
        let entry = placeholder(in: context)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        var data: QuotaData? = nil
        let fileManager = FileManager.default
        let homeDir = fileManager.homeDirectoryForCurrentUser
        let fileURL = homeDir.appendingPathComponent("Documents/quota.json")
        
        if let saved = try? Data(contentsOf: fileURL) {
            data = try? JSONDecoder().decode(QuotaData.self, from: saved)
        }
        
        var entries: [SimpleEntry] = []
        let currentDate = Date()
        
        // Generate an entry every minute for the next 2 hours
        for minuteOffset in 0 ..< 120 {
            if let entryDate = Calendar.current.date(byAdding: .minute, value: minuteOffset, to: currentDate) {
                entries.append(SimpleEntry(date: entryDate, data: data))
            }
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
    let cachedPercentage: Double
    let resetTimeString: String
    let currentDate: Date
    let cycleDurationSeconds: TimeInterval
    
    var indicatorText: (String, Color)? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let cycleEnd = formatter.date(from: resetTimeString) else { return nil }
        
        let cycleStart = cycleEnd.addingTimeInterval(-cycleDurationSeconds)
        let timeElapsed = currentDate.timeIntervalSince(cycleStart)
        
        let actualPct: Double = (currentDate >= cycleEnd) ? 1.0 : cachedPercentage
        
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
    
    func formatRefreshText(from dateString: String, currentDate: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let targetDate = formatter.date(from: dateString) else {
            return "Quota available"
        }
        
        let timeInterval = targetDate.timeIntervalSince(currentDate)
        
        if timeInterval <= 0 {
            return "Quota available"
        }
        
        let hours = Int(timeInterval) / 3600
        let minutes = (Int(timeInterval) % 3600) / 60
        
        if hours > 0 {
            return "Refreshes in \(hours)h \(minutes)m"
        } else {
            return "Refreshes in \(minutes)m"
        }
    }
    
    func getEffectivePercentage(cachedPercentage: Double, resetTime: String, currentDate: Date) -> Double {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let targetDate = formatter.date(from: resetTime) else {
            return cachedPercentage
        }
        
        if targetDate.timeIntervalSince(currentDate) <= 0 {
            return 1.0
        }
        
        return cachedPercentage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let d = entry.data {
                VStack(alignment: .leading, spacing: 10) {
                    Text("GEMINI MODELS").bold()
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Five Hour Limit Remaining").bold()
                            Spacer()
                            PacingIndicator(cachedPercentage: d.gemini5hRemaining, resetTimeString: d.gemini5hResetTime, currentDate: entry.date, cycleDurationSeconds: 5 * 3600)
                        }
                        HStack(spacing: 0) {
                            Text("  [")
                            let effPct = getEffectivePercentage(cachedPercentage: d.gemini5hRemaining, resetTime: d.gemini5hResetTime, currentDate: entry.date)
                            QuotaBar(percentage: effPct)
                            Text("] ")
                            Text(String(format: "%.0f%%", effPct * 100)).foregroundColor(.black).bold()
                        }
                        Text("  " + formatRefreshText(from: d.gemini5hResetTime, currentDate: entry.date)).foregroundColor(.green)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Weekly Limit Remaining").bold()
                            Spacer()
                            PacingIndicator(cachedPercentage: d.geminiWeeklyRemaining, resetTimeString: d.geminiWeeklyResetTime, currentDate: entry.date, cycleDurationSeconds: 7 * 24 * 3600)
                        }
                        HStack(spacing: 0) {
                            Text("  [")
                            let effPct = getEffectivePercentage(cachedPercentage: d.geminiWeeklyRemaining, resetTime: d.geminiWeeklyResetTime, currentDate: entry.date)
                            QuotaBar(percentage: effPct)
                            Text("] ")
                            Text(String(format: "%.0f%%", effPct * 100)).foregroundColor(.black).bold()
                        }
                        Text("  " + formatRefreshText(from: d.geminiWeeklyResetTime, currentDate: entry.date)).foregroundColor(.green)
                    }
                }
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("CLAUDE AND GPT MODELS").bold()
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Five Hour Limit Remaining").bold()
                            Spacer()
                            PacingIndicator(cachedPercentage: d.claude5hRemaining, resetTimeString: d.claude5hResetTime, currentDate: entry.date, cycleDurationSeconds: 5 * 3600)
                        }
                        HStack(spacing: 0) {
                            Text("  [")
                            let effPct = getEffectivePercentage(cachedPercentage: d.claude5hRemaining, resetTime: d.claude5hResetTime, currentDate: entry.date)
                            QuotaBar(percentage: effPct)
                            Text("] ")
                            Text(String(format: "%.0f%%", effPct * 100)).foregroundColor(.black).bold()
                        }
                        Text("  " + formatRefreshText(from: d.claude5hResetTime, currentDate: entry.date)).foregroundColor(.green)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Weekly Limit Remaining").bold()
                            Spacer()
                            PacingIndicator(cachedPercentage: d.claudeWeeklyRemaining, resetTimeString: d.claudeWeeklyResetTime, currentDate: entry.date, cycleDurationSeconds: 7 * 24 * 3600)
                        }
                        HStack(spacing: 0) {
                            Text("  [")
                            let effPct = getEffectivePercentage(cachedPercentage: d.claudeWeeklyRemaining, resetTime: d.claudeWeeklyResetTime, currentDate: entry.date)
                            QuotaBar(percentage: effPct)
                            Text("] ")
                            Text(String(format: "%.0f%%", effPct * 100)).foregroundColor(.black).bold()
                        }
                        Text("  " + formatRefreshText(from: d.claudeWeeklyResetTime, currentDate: entry.date)).foregroundColor(.green)
                    }
                }
            } else {
                Text("No data yet. Waiting for update...")
            }
        }
        .font(.system(size: 14, weight: .regular, design: .monospaced))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
        .foregroundColor(.black)
    }
}

@main
struct TokenPaceExtension: Widget {
    let kind: String = "TokenPaceExtension"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            TokenPaceEntryView(entry: entry)
                .containerBackground(Color.white, for: .widget)
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
