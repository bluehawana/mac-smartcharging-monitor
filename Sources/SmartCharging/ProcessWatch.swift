import Foundation

/// Who is actually eating the power right now.
///
/// Knowing you're 21 W short is useful. Knowing *oMLX* is why is what lets
/// someone decide whether to pause the model or go buy a bigger charger.
/// macOS doesn't expose per-process wattage without private API, so this
/// reports CPU share — and says so — rather than inventing watts.
struct RunningLoad: Identifiable, Equatable {
    let id: Int32
    let name: String
    let cpuPercent: Double
    let isAIRuntime: Bool
}

enum ProcessWatch {

    /// Local-inference runtimes, matched case-insensitively against the
    /// executable name. These are the processes that turn a marginal
    /// charger into a draining one.
    private static let aiRuntimes = [
        "ollama", "omlx", "mlx", "llama", "llamacpp", "lm studio", "lmstudio",
        "vllm", "koboldcpp", "text-generation", "gpt4all", "jan"
    ]

    static func isAIRuntime(_ name: String) -> Bool {
        let lower = name.lowercased()
        return aiRuntimes.contains { lower.contains($0) }
    }

    /// Top processes by CPU. Returns [] rather than throwing — this is a
    /// nice-to-have panel, never a reason to fail a reading.
    static func topLoads(limit: Int = 4) -> [RunningLoad] {
        guard let output = run("/bin/ps", ["-Aceo", "pid,pcpu,comm", "-r"]) else { return [] }

        var loads: [RunningLoad] = []
        for line in output.split(separator: "\n").dropFirst() {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 3,
                  let pid = Int32(parts[0]),
                  let cpu = Double(parts[1]) else { continue }

            let name = parts[2...].joined(separator: " ")
            if cpu < 5 { break }                    // sorted desc; nothing below matters
            if name == "ps" { continue }

            loads.append(RunningLoad(id: pid,
                                     name: name,
                                     cpuPercent: cpu,
                                     isAIRuntime: isAIRuntime(name)))
            if loads.count >= limit { break }
        }
        return loads
    }

    private static func run(_ path: String, _ args: [String]) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice

        do { try proc.run() } catch { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}
