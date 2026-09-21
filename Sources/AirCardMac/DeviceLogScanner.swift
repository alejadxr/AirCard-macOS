@preconcurrency import Foundation

enum DeviceLogScanner {
    static func lines(helper: URL, udid: String) -> AsyncThrowingStream<String, Error> {
        let controller = ProcessTerminationController()
        let stream = AsyncThrowingStream<String, Error> { continuation in
            let worker = Task.detached(priority: .userInitiated) {
                let process = Process()
                let pipe = Pipe()
                process.executableURL = helper
                process.arguments = ["syslog", udid]
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice
                controller.install(process)

                do {
                    try process.run()
                    while true {
                        try Task.checkCancellation()
                        let data = pipe.fileHandleForReading.availableData
                        if data.isEmpty { break }
                        let text = String(decoding: data, as: UTF8.self)
                        for line in text.split(whereSeparator: \.isNewline) {
                            continuation.yield(String(line))
                        }
                    }
                    process.waitUntilExit()
                    if !Task.isCancelled && process.terminationStatus != 0 {
                        throw AirCardError.processFailed("El monitor de syslog terminó con código \(process.terminationStatus).")
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                controller.terminate()
                worker.cancel()
            }
        }
        return stream
    }
}
