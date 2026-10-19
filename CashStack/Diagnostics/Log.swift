import os

/// What the app is doing, for Console.app and the sysdiagnose a person can
/// send support. Interpolated values are private unless marked `.public`, so
/// a shared log doesn't carry names, balances, paths with ids, or tokens —
/// only status codes, error codes and the like are public.
enum Log {
    private static let subsystem = "com.bokscot.cashstack"

    static let api = Logger(subsystem: subsystem, category: "api")
    static let session = Logger(subsystem: subsystem, category: "session")
    static let bank = Logger(subsystem: subsystem, category: "bank")
    static let diagnostics = Logger(subsystem: subsystem, category: "diagnostics")
}
