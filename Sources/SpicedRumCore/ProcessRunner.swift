import Foundation
import Darwin

private func consumeTimeoutSignal(_ signal: DispatchSemaphore) -> Bool {
    signal.wait(timeout: .now()) == .success
}

public enum ProcessRunner {
    public static func run(_ executable: URL, _ arguments: [String], environment: [String: String] = ProcessInfo.processInfo.environment, directory: URL, log: URL, label: String? = nil, timeout: TimeInterval? = nil) async throws {
        let process = Process()
        process.executableURL = executable; process.arguments = arguments
        process.environment = environment; process.currentDirectoryURL = directory
        if !FileManager.default.fileExists(atPath: log.path) {
            guard FileManager.default.createFile(atPath: log.path, contents: nil) else { throw RumError.message("Cannot create log at \(log.path).") }
        }
        let output = try FileHandle(forWritingTo: log)
        defer { try? output.close() }
        try output.seekToEnd()
        if let label { try output.write(contentsOf: Data("\n[\(Date())] \(label): \(arguments.joined(separator: " "))\n".utf8)) }
        process.standardOutput = output; process.standardError = output
        let timeoutFired = DispatchSemaphore(value: 0)
        let started = ProcessInfo.processInfo.systemUptime
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do { try process.run() } catch { continuation.resume(throwing: error); return }
            if let timeout {
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    if process.isRunning {
                        timeoutFired.signal()
                        process.terminate()
                        DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                        }
                    }
                }
            }
        }
        let timedOut = consumeTimeoutSignal(timeoutFired)
        let result = timedOut ? "timed out after \(Int(timeout ?? 0)) seconds"
            : process.terminationReason == .uncaughtSignal ? "was terminated by signal \(status)" : "exited with code \(status)"
        let elapsed = String(format: "%.1f", ProcessInfo.processInfo.systemUptime - started)
        // Capture the outcome even when macOS kills the loader before it can write stderr.
        if label != nil || status != 0 || timedOut {
            try output.write(contentsOf: Data("\n[\(Date())] \(label ?? executable.lastPathComponent) \(result) (elapsed \(elapsed)s).\n".utf8))
        }
        guard status == 0 && !timedOut else {
            throw RumError.message("\(label ?? executable.lastPathComponent) \(result). See \(log.path) for details.")
        }
    }

    public static func capture(_ executable: URL, _ arguments: [String], environment: [String: String] = ProcessInfo.processInfo.environment, timeout: TimeInterval? = nil) async throws -> String {
        let folder = FileManager.default.temporaryDirectory
        let log = folder.appendingPathComponent("SpicedRum-command-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: log) }
        do { try await run(executable, arguments, environment: environment, directory: folder, log: log, timeout: timeout) }
        catch { throw RumError.message(error.localizedDescription + "\n" + String(((try? String(contentsOf: log)) ?? "").prefix(3000))) }
        return try String(contentsOf: log, encoding: .utf8)
    }
}
