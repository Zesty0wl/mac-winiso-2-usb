import Foundation
import os

// Result from a completed process execution
struct ProcessResult: Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String

    var succeeded: Bool { exitCode == 0 }
}

// Thread-safe accumulator for process output across concurrency boundaries
private final class OutputAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var _stdout = ""
    private var _stderr = ""

    func appendStdout(_ chunk: String) {
        lock.lock()
        _stdout += chunk
        lock.unlock()
    }

    func appendStderr(_ chunk: String) {
        lock.lock()
        _stderr += chunk
        lock.unlock()
    }

    func getStdout() -> String {
        lock.lock()
        defer { lock.unlock() }
        return _stdout
    }

    func getStderr() -> String {
        lock.lock()
        defer { lock.unlock() }
        return _stderr
    }
}

// Utility for executing system processes with output capture
enum ProcessRunner {
    private static let logger = Logger(subsystem: "com.winiso2usb.app", category: "ProcessRunner")

    // Run a process synchronously on a background thread, capturing all output
    static func run(
        _ executable: String,
        arguments: [String] = [],
        environment: [String: String]? = nil
    ) async throws -> ProcessResult {
        let executableCopy = executable
        let argumentsCopy = arguments
        let environmentCopy = environment

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executableCopy)
                process.arguments = argumentsCopy
                if let env = environmentCopy {
                    var merged = ProcessInfo.processInfo.environment
                    for (k, v) in env { merged[k] = v }
                    process.environment = merged
                }

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                let cmd = "\(executableCopy) \(argumentsCopy.joined(separator: " "))"
                logger.debug("Running: \(cmd)")

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                let result = ProcessResult(
                    exitCode: process.terminationStatus,
                    stdout: String(data: stdoutData, encoding: .utf8) ?? "",
                    stderr: String(data: stderrData, encoding: .utf8) ?? ""
                )

                if !result.succeeded {
                    logger.error("Process failed (\(result.exitCode)): \(result.stderr)")
                }

                continuation.resume(returning: result)
            }
        }
    }

    // Run a process with real-time stdout line callback for progress tracking
    static func runWithOutput(
        _ executable: String,
        arguments: [String] = [],
        onLine: @escaping @Sendable (String) -> Void
    ) async throws -> ProcessResult {
        let executableCopy = executable
        let argumentsCopy = arguments

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executableCopy)
                process.arguments = argumentsCopy

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                let cmd = "\(executableCopy) \(argumentsCopy.joined(separator: " "))"
                logger.debug("Running with output: \(cmd)")

                let accumulator = OutputAccumulator()

                stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty else { return }
                    if let chunk = String(data: data, encoding: .utf8) {
                        accumulator.appendStdout(chunk)
                        let lines = chunk.components(separatedBy: .newlines)
                        for line in lines where !line.isEmpty {
                            onLine(line)
                        }
                    }
                }

                stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty else { return }
                    if let chunk = String(data: data, encoding: .utf8) {
                        accumulator.appendStderr(chunk)
                    }
                }

                process.terminationHandler = { proc in
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil

                    let result = ProcessResult(
                        exitCode: proc.terminationStatus,
                        stdout: accumulator.getStdout(),
                        stderr: accumulator.getStderr()
                    )
                    continuation.resume(returning: result)
                }

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // Run diskutil with -plist flag and parse the result as a property list dictionary
    static func runDiskutil(_ arguments: [String]) async throws -> [String: Any] {
        let result = try await run("/usr/sbin/diskutil", arguments: ["-plist"] + arguments)
        guard result.succeeded else {
            throw WINISO2USBError.processError(
                "diskutil \(arguments.joined(separator: " ")) failed: \(result.stderr)"
            )
        }
        guard let data = result.stdout.data(using: .utf8),
              let plist = try PropertyListSerialization.propertyList(
                  from: data, format: nil
              ) as? [String: Any] else {
            throw WINISO2USBError.processError("Failed to parse diskutil plist output")
        }
        return plist
    }
}
