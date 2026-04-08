import Foundation

/// Cloud-sync snapshot type for terminal accessory preferences.
///
/// This currently mirrors `TerminalAccessoryProfile` so call sites can
/// pass profile values directly through CloudKit sync APIs.
typealias TerminalAccessoryProfileSnapshot = TerminalAccessoryProfile
