import Foundation
import Darwin

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
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do { try process.run() } catch { continuation.resume(throwing: error); return }
            if let timeout {
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    if process.isRunning {
                        process.terminate()
                        DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                        }
                    }
                }
            }
        }
        guard status == 0 else { throw RumError.message("\(label ?? executable.lastPathComponent) exited with code \(status). See \(log.path) for details.") }
    }

    public static func capture(_ executable: URL, _ arguments: [String], environment: [String: String] = ProcessInfo.processInfo.environment) async throws -> String {
        let folder = FileManager.default.temporaryDirectory
        let log = folder.appendingPathComponent("SpicedRum-command-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: log) }
        do { try await run(executable, arguments, environment: environment, directory: folder, log: log) }
        catch { throw RumError.message(error.localizedDescription + "\n" + String(((try? String(contentsOf: log)) ?? "").prefix(3000))) }
        return try String(contentsOf: log, encoding: .utf8)
    }
}
