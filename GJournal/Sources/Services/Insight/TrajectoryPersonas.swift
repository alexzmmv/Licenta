import Foundation

/// Deterministic synthetic personas for validating the trajectory biomarkers before any UI
/// investment (plan §2.2 step 10). Each persona is engineered so exactly one metric fires:
///   - ruminator : cyclic revisiting  -> high Loop Persistence
///   - explorer  : spreading disk      -> high Flare Index, low LP
///   - recoverer : moving off distress -> positive Semantic Recovery Velocity
enum TrajectoryPersonas {

    private static let base = Date(timeIntervalSince1970: 1_700_000_000)  // fixed anchor
    private static let count = 24
    private static let spanDays = 30.0

    private static func date(_ i: Int) -> Date {
        base.addingTimeInterval(Double(i) / Double(count - 1) * spanDays * 86_400)
    }

    // MARK: - Personas

    /// Ring in embedding space: entries repeatedly revisit the same ~8 semantic locations,
    /// leaving a topological hole -> a persistent β1 loop.
    static func personaRuminator() -> [TrajectoryPoint] {
        var rng = SplitMix64(seed: 101)
        let period = 8.0
        return (0..<count).map { i in
            let theta = 2 * Double.pi * Double(i) / period
            let r = 1.0 + rng.nextGaussian() * 0.03
            let e = [Foundation.cos(theta) * r + rng.nextGaussian() * 0.02,
                     Foundation.sin(theta) * r + rng.nextGaussian() * 0.02]
            return TrajectoryPoint(date: date(i), embedding: e, valence: rng.nextUnit() * 2 - 1)
        }
    }

    /// Filled disk: entries spread out to occupy new semantic territory, no hole -> high flare.
    static func personaExplorer() -> [TrajectoryPoint] {
        var rng = SplitMix64(seed: 202)
        return (0..<count).map { i in
            let radius = rng.nextUnit().squareRoot() * 1.5   // uniform over the disk
            let theta = 2 * Double.pi * rng.nextUnit()
            let e = [Foundation.cos(theta) * radius, Foundation.sin(theta) * radius]
            return TrajectoryPoint(date: date(i), embedding: e, valence: rng.nextUnit() * 2 - 1)
        }
    }

    /// Near-1D drift: starts at the low-valence distress anchor and moves steadily away over
    /// time -> positive SRV, no hole, negligible flare.
    static func personaRecoverer() -> [TrajectoryPoint] {
        var rng = SplitMix64(seed: 303)
        return (0..<count).map { i in
            let progress = Double(i) / Double(count - 1)
            let e = [progress * 3.0 + rng.nextGaussian() * 0.02,
                     rng.nextGaussian() * 0.03]
            let valence = -0.8 + 1.6 * progress   // distressed -> pleasant
            return TrajectoryPoint(date: date(i), embedding: e, valence: valence)
        }
    }
}
