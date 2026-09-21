@preconcurrency import Foundation

struct ProcessResult: Sendable {
    let status: Int32
    let stdout: Data
    let stderr: Data

    var stdoutString: String {
        String(decoding: stdout, as: UTF8.self)
    }

    var stderrString: String {
        String(decoding: stderr, as: UTF8.self)
    }
}

final class ProcessTerminationController: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    // Invariant: process and cancelled are protected by lock. The worker owns
    // all normal Process I/O; cancellation only calls Process.terminate().
    func install(_ process: Process) {
        lock.lock()
        self.process = process
        let shouldTerminate = cancelled
        lock.unlock()
        if shouldTerminate, process.isRunning { process.terminate() }
    }

    func terminate() {
        lock.lock()
        cancelled = true
        let process = self.process
        lock.unlock()
        if let process, process.isRunning { process.terminate() }
    }
}

enum ProcessRunner {
    static func run(
        executable: URL,
        arguments: [String],
        timeout: Duration = .seconds(120)
    ) async throws -> ProcessResult {
        try Task.checkCancellation()

        let controller = ProcessTerminationController()
        let result = try await withTaskCancellationHandler(operation: {
            try await Task.detached(priority: .userInitiated) {
                try Task.checkCancellation()
                let process = Process()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.executableURL = executable
                process.arguments = arguments
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe
                process.environment = ProcessInfo.processInfo.environment
                controller.install(process)

                do {
                    try process.run()
                } catch {
                    throw AirCardError.processFailed(
                        "No se pudo ejecutar \(executable.path): \(error.localizedDescription)"
                    )
                }

                let deadline = ContinuousClock.now + timeout
                while process.isRunning {
                    if ContinuousClock.now >= deadline {
                        controller.terminate()
                        throw AirCardError.processFailed(
                            "El proceso \(executable.lastPathComponent) excedió el tiempo límite."
                        )
                    }
                    try await Task.sleep(for: .milliseconds(100))
                }

                return ProcessResult(
                    status: process.terminationStatus,
                    stdout: stdoutPipe.fileHandleForReading.readDataToEndOfFile(),
                    stderr: stderrPipe.fileHandleForReading.readDataToEndOfFile()
                )
            }.value
        }, onCancel: {
            controller.terminate()
        })

        return result
    }
}
