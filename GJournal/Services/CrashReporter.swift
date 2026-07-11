import MetricKit
import Foundation

/// Subscribes to MetricKit to receive crash diagnostics and app performance metrics.
/// Logs crash reports via AppLogger so they surface in the Console on-device.
/// No third-party SDK — all data stays on device.
final class CrashReporter: NSObject, MXMetricManagerSubscriber {

    static let shared = CrashReporter()
    private override init() { super.init() }

    func start() {
        MXMetricManager.shared.add(self)
        AppLogger.log("[CrashReporter] MetricKit subscriber registered.")
    }

    func stop() {
        MXMetricManager.shared.remove(self)
    }

    // MARK: - MXMetricManagerSubscriber

    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            AppLogger.log("[MetricKit] Metric payload received for \(payload.timeStampBegin)–\(payload.timeStampEnd)")
            if payload.applicationLaunchMetrics != nil {
                AppLogger.log("[MetricKit] Launch metrics present in payload.")
            }
            if let memory = payload.memoryMetrics {
                AppLogger.log("[MetricKit] Peak memory: \(memory.peakMemoryUsage)")
            }
        }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            if let crashes = payload.crashDiagnostics, !crashes.isEmpty {
                for crash in crashes {
                    let signal = crash.signal ?? 0
                    let exType = crash.exceptionType ?? 0
                    let exCode = crash.exceptionCode ?? 0
                    let reason = crash.terminationReason ?? "unknown"
                    AppLogger.error("[MetricKit/Crash] signal=\(signal) exType=\(exType) exCode=\(exCode) reason=\(reason)")
                    if let stackJson = String(data: crash.callStackTree.jsonRepresentation(), encoding: .utf8) {
                        AppLogger.error("[MetricKit/Crash] Stack (JSON):\n\(stackJson.prefix(1000))")
                    }
                }
            }
            if let hangs = payload.hangDiagnostics, !hangs.isEmpty {
                AppLogger.error("[MetricKit/Hang] \(hangs.count) hang diagnostic(s) received")
            }
            if let cpuEx = payload.cpuExceptionDiagnostics, !cpuEx.isEmpty {
                AppLogger.error("[MetricKit/CPU] \(cpuEx.count) CPU exception(s)")
            }
            if let diskEx = payload.diskWriteExceptionDiagnostics, !diskEx.isEmpty {
                AppLogger.error("[MetricKit/Disk] \(diskEx.count) disk-write exception(s)")
            }
        }
    }
}
