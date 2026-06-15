import Foundation
import UsageCore

func runUsageLevelTests() {
    test("below warning threshold is normal") {
        expectEqual(UsageLevel(utilization: 0, thresholdsEnabled: true), .normal)
        expectEqual(UsageLevel(utilization: 50, thresholdsEnabled: true), .normal)
        expectEqual(UsageLevel(utilization: 89.9, thresholdsEnabled: true), .normal)
    }

    test("at or above 90 is warning") {
        expectEqual(UsageLevel(utilization: 90, thresholdsEnabled: true), .warning)
        expectEqual(UsageLevel(utilization: 99.9, thresholdsEnabled: true), .warning)
    }

    test("at or above 100 is critical") {
        expectEqual(UsageLevel(utilization: 100, thresholdsEnabled: true), .critical)
        expectEqual(UsageLevel(utilization: 140, thresholdsEnabled: true), .critical)
    }

    test("thresholds disabled is always normal") {
        expectEqual(UsageLevel(utilization: 95, thresholdsEnabled: false), .normal)
        expectEqual(UsageLevel(utilization: 100, thresholdsEnabled: false), .normal)
    }

    test("nil window is normal") {
        expectEqual(UsageLevel(utilization: nil, thresholdsEnabled: true), .normal)
    }
}
