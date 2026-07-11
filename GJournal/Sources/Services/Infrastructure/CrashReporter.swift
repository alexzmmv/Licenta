import MetricKit
import Foundation

/// Subscribes to MetricKit for crash diagnostics and app performance metrics.
///
/// Diagnostic payloads (crashes, hangs, CPU/disk-write exceptions) are delivered by
/// MetricKit exactly once — if they aren't persisted immediately they are lost forever.
/// They are therefore written unconditionally to Application Support/CrashReports
/// (rotated, newest 20 kept), independent of the debug-logging toggle that gates
/// `AppLogger`. No third-party SDK — all data stays on device; payloads contain call
/// stacks and system metadata only, never journal content.
///
/// `nonisolated`: MXMetricManager calls its subscribers on a private background queue,
/// so this type opts out of the target's default MainActor isolation.
nonisolated final class CrashReporter: NSObject, MXMetricManagerSubscriber {

    static let shared = CrashReporter()
    private override init() { super.init() }

    /// Maximum number of diagnostic payload files kept on disk.
    private static let maxStoredReports = 20

    /// Directory where diagnostic payloads are persisted. Created on demand.
    static var reportsDirectory: URL? {
        guard let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else { return nil }
        let dir = base.appendingPathComponent("CrashReports", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        return dir
    }

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
            // Persist first — MetricKit will not redeliver this payload.
            persist(payload)

            // Console summaries (visible only when debug logging is enabled).
            if let crashes = payload.crashDiagnostics, !crashes.isEmpty {
                for crash in crashes {
                    let signal = crash.signal ?? 0
                    let exType = crash.exceptionType ?? 0
                    let exCode = crash.exceptionCode ?? 0
                    let reason = crash.terminationReason ?? "unknown"
                    AppLogger.error("[MetricKit/Crash] signal=\(signal) exType=\(exType) exCode=\(exCode) reason=\(reason)")
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

    // MARK: - Persistence

    /// Write the full payload JSON to disk and prune old reports.
    /// Deliberately not gated on any toggle — a dropped payload is unrecoverable.
    private func persist(_ payload: MXDiagnosticPayload) {
        guard let dir = Self.reportsDirectory else { return }
        let stamp = UInt(payload.timeStampEnd.timeIntervalSince1970)
        let file = dir.appendingPathComponent("diagnostic-\(stamp)-\(UUID().uuidString.prefix(8)).json")
        do {
            try payload.jsonRepresentation().write(to: file, options: [.atomic, .completeFileProtectionUnlessOpen])
            AppLogger.log("[CrashReporter] Diagnostic payload persisted to \(file.lastPathComponent)")
        } catch {
            AppLogger.error("[CrashReporter] Failed to persist diagnostic payload: \(error)")
        }
        pruneOldReports(in: dir)
    }

    /// Keep only the newest `maxStoredReports` files (by creation date).
    private func pruneOldReports(in dir: URL) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.creationDateKey]),
              files.count > Self.maxStoredReports else { return }
        let sorted = files.sorted { a, b in
            let da = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return da < db
        }
        for file in sorted.prefix(files.count - Self.maxStoredReports) {
            try? fm.removeItem(at: file)
        }
    }
}
