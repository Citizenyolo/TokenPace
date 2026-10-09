import Foundation
import Darwin

struct QuotaFetcher {
    static func fetchQuota() -> QuotaData? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return fetchQuota(executable: home.appendingPathComponent(".local/bin/agy"))
    }

    static func fetchQuota(executable: URL, timeout: TimeInterval = QuotaPolicy.fetchTimeout) -> QuotaData? {
        let task = Process()
        task.executableURL = executable
        task.arguments = ["--output-format", "json", "-p", "/usage"]

        // Drain stdout without pipe-buffer deadlocks; cap both runtime and output size.
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        let output = QuotaOutputBuffer()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            output.drain(handle)
        }
        defer {
            pipe.fileHandleForReading.readabilityHandler = nil
            try? pipe.fileHandleForReading.close()
            try? pipe.fileHandleForWriting.close()
        }
        do {
            try task.run()
            try? pipe.fileHandleForWriting.close()
            let deadline = ProcessInfo.processInfo.systemUptime + timeout
            while (task.isRunning || !output.finished) && ProcessInfo.processInfo.systemUptime < deadline && !output.overflow {
                Thread.sleep(forTimeInterval: 0.02)
            }
            guard !task.isRunning, output.finished, !output.overflow else {
                // Kill only the child owned by this fetch, including a SIGTERM-resistant CLI.
                if task.isRunning {
                    kill(task.processIdentifier, SIGKILL)
                    task.waitUntilExit()
                }
                return nil
            }
            task.waitUntilExit()
            pipe.fileHandleForReading.readabilityHandler = nil
            guard task.terminationStatus == 0, !output.overflow else { return nil }
            return parse(output.data, fetchedAt: Date())
        } catch {
            print("Failed to run agy: \(error)")
            return nil
        }
    }

    static func parse(_ data: Data, fetchedAt: Date) -> QuotaData? {
        do {
            let usageResponse = try JSONDecoder().decode(UsageResponse.self, from: data)
            guard usageResponse.status == "SUCCESS", usageResponse.command.name == "usage" else { return nil }
            
            var result = QuotaData(
                geminiWeeklyRemaining: 0, geminiWeeklyResetTime: "",
                gemini5hRemaining: 0, gemini5hResetTime: "",
                claudeWeeklyRemaining: 0, claudeWeeklyResetTime: "",
                claude5hRemaining: 0, claude5hResetTime: ""
            )
            
            var seen = Set<String>()
            let required = Set(["gemini-weekly", "gemini-5h", "3p-weekly", "3p-5h"])
            for group in usageResponse.command.data.groups {
                for bucket in group.buckets where required.contains(bucket.id) {
                    let expectedGroup = bucket.id.hasPrefix("gemini-") ? "Gemini Models" : "Claude and GPT models"
                    guard group.name == expectedGroup, seen.insert(bucket.id).inserted,
                          bucket.remaining_fraction != nil, bucket.reset_time != nil else { return nil }
                }
                if group.name == "Gemini Models" {
                    for bucket in group.buckets {
                        if bucket.id == "gemini-weekly" {
                            result.geminiWeeklyRemaining = bucket.remaining_fraction ?? 0
                            result.geminiWeeklyResetTime = bucket.reset_time ?? ""
                        } else if bucket.id == "gemini-5h" {
                            result.gemini5hRemaining = bucket.remaining_fraction ?? 0
                            result.gemini5hResetTime = bucket.reset_time ?? ""
                        }
                    }
                } else if group.name == "Claude and GPT models" {
                    for bucket in group.buckets {
                        if bucket.id == "3p-weekly" {
                            result.claudeWeeklyRemaining = bucket.remaining_fraction ?? 0
                            result.claudeWeeklyResetTime = bucket.reset_time ?? ""
                        } else if bucket.id == "3p-5h" {
                            result.claude5hRemaining = bucket.remaining_fraction ?? 0
                            result.claude5hResetTime = bucket.reset_time ?? ""
                        }
                    }
                }
            }
            
            guard seen == required, result.isValid(at: fetchedAt) else { return nil }
            result.fetchedAt = fetchedAt
            result.producerRevision = QuotaBuildIdentity.revision
            return result
            
        } catch {
            print("Failed to run agy or decode json: \(error)")
            return nil
        }
    }
}

private final class QuotaOutputBuffer {
    private let lock = NSLock()
    private var bytes = Data()
    private var exceeded = false
    private var eof = false
    var finished: Bool { lock.lock(); defer { lock.unlock() }; return eof }
    var data: Data { lock.lock(); defer { lock.unlock() }; return bytes }
    var overflow: Bool { lock.lock(); defer { lock.unlock() }; return exceeded }

    func drain(_ handle: FileHandle) {
        lock.lock(); defer { lock.unlock() }
        guard !eof else { return }
        let chunk = handle.availableData
        if chunk.isEmpty { eof = true }
        appendLocked(chunk)
    }

    private func appendLocked(_ data: Data) {
        if bytes.count + data.count > 1_048_576 { exceeded = true }
        if !exceeded { bytes.append(data) }
    }
}
