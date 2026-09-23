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
                    // syslog_relay on iOS 18 terminates records with NUL, and
                    // a record can straddle two reads, so bytes are buffered
                    // until a full line is available.
                    var pending = Data()
                    while true {
                        try Task.checkCancellation()
                        let data = pipe.fileHandleForReading.availableData
                        if data.isEmpty { break }
                        pending.append(data)
                        var lineStart = pending.startIndex
                        for index in pending.indices where [0x0A, 0x0D, 0x00].contains(pending[index]) {
                            if index > lineStart {
                                continuation.yield(String(decoding: pending[lineStart..<index], as: UTF8.self))
                            }
                            lineStart = index + 1
                        }
                        pending = Data(pending[lineStart...])
                        if pending.count > 1 << 20 { pending.removeAll(keepingCapacity: true) }
                    }
                    if !pending.isEmpty {
                        continuation.yield(String(decoding: pending, as: UTF8.self))
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
