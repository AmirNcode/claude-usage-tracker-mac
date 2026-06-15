import Foundation

/// Severity of a usage window, used to color the menu bar percentage.
/// `warning` at >=90%, `critical` at >=100%. When thresholds are disabled the
/// level is always `.normal` and the user's custom color is used as-is.
public enum UsageLevel: Equatable {
    case normal
    case warning
    case critical

    public static let warningThreshold = 90.0
    public static let criticalThreshold = 100.0

    public init(utilization: Double?, thresholdsEnabled: Bool) {
        guard thresholdsEnabled, let utilization else {
            self = .normal
            return
        }
        if utilization >= Self.criticalThreshold {
            self = .critical
        } else if utilization >= Self.warningThreshold {
            self = .warning
        } else {
            self = .normal
        }
    }
}
