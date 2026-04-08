import Foundation
import os.log

enum StartupSafety {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app.vivy.VivyTerm", category: "Startup")

    static func runStartupAudit() {
        clearDeprecatedFeatureFlags()
        validateCriticalDefaults()
    }

    private static func clearDeprecatedFeatureFlags() {
        let defaults = UserDefaults.standard
        [
            "iCloudSyncEnabled",
            "syncEnabled",
            "transcriptionProvider",
            "mlxWhisperModelId",
            "mlxParakeetModelId"
        ].forEach { key in
            if defaults.object(forKey: key) != nil {
                defaults.removeObject(forKey: key)
                logger.info("Removed deprecated startup key: \(key)")
            }
        }
    }

    private static func validateCriticalDefaults() {
        let defaults = UserDefaults.standard

        if let value = defaults.object(forKey: "terminalFontSize") as? Double, value <= 0 {
            defaults.set(12.0, forKey: "terminalFontSize")
            logger.warning("Invalid terminalFontSize detected; reset to safe default")
        }
    }
}
