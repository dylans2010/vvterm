//
//  VVTermApp.swift
//  VVTerm
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

@main
struct VVTermApp: App {
    init() {
        TerminalDefaults.applyIfNeeded()
        StartupSafety.runStartupAudit()
    }

    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #else
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

    @StateObject private var ghosttyApp = Ghostty.App(autoStart: false)
    @StateObject private var terminalThemeManager = TerminalThemeManager.shared
    @StateObject private var terminalAccessoryPreferencesManager = TerminalAccessoryPreferencesManager.shared

    // Welcome screen flag
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false

    // App language
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.system.rawValue

    // Terminal settings to watch for changes
    @AppStorage("terminalFontName") private var terminalFontName = "JetBrainsMono Nerd Font"
    @AppStorage("terminalFontSize") private var terminalFontSize = 8.0
    @AppStorage("terminalThemeName") private var terminalThemeName = "Aizen Dark"
    @AppStorage("terminalThemeNameLight") private var terminalThemeNameLight = "Aizen Light"
    @AppStorage("terminalUsePerAppearanceTheme") private var usePerAppearanceTheme = true

    private var activeCustomThemeVersionToken: String {
        let activeThemes = terminalThemeManager.customThemes.filter { !$0.isDeleted }
        let byName = Dictionary(
            activeThemes.map { ($0.name, $0) },
            uniquingKeysWith: { current, candidate in
                current.updatedAt >= candidate.updatedAt ? current : candidate
            }
        )

        let darkVersion = byName[terminalThemeName]?.updatedAt.timeIntervalSince1970 ?? 0
        let lightVersion = byName[terminalThemeNameLight]?.updatedAt.timeIntervalSince1970 ?? 0

        if usePerAppearanceTheme {
            return "\(darkVersion):\(lightVersion)"
        }

        return "\(darkVersion)"
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            let appLocale = AppLanguage(rawValue: appLanguage)?.locale ?? Locale.current
            AppLockContainer {
                Group {
                    #if os(iOS)
                    iOSContentView()
                        .environmentObject(ghosttyApp)
                        .environmentObject(terminalThemeManager)
                        .environmentObject(terminalAccessoryPreferencesManager)
                        .modifier(AppearanceModifier())
                        .task(id: "\(terminalFontName)\(terminalFontSize)\(terminalThemeName)\(terminalThemeNameLight)\(usePerAppearanceTheme)\(activeCustomThemeVersionToken)") {
                            ghosttyApp.reloadConfig()
                        }
                        .sheet(isPresented: .init(
                            get: { !hasSeenWelcome },
                            set: { if !$0 { hasSeenWelcome = true } }
                        )) {
                            WelcomeView(hasSeenWelcome: $hasSeenWelcome)
                                .interactiveDismissDisabled()
                        }
                    #else
                    ContentView()
                        .environmentObject(ghosttyApp)
                        .environmentObject(terminalThemeManager)
                        .environmentObject(terminalAccessoryPreferencesManager)
                        .modifier(AppearanceModifier())
                        .task(id: "\(terminalFontName)\(terminalFontSize)\(terminalThemeName)\(terminalThemeNameLight)\(usePerAppearanceTheme)\(activeCustomThemeVersionToken)") {
                            ghosttyApp.reloadConfig()
                        }
                        .sheet(isPresented: .init(
                            get: { !hasSeenWelcome },
                            set: { if !$0 { hasSeenWelcome = true } }
                        )) {
                            WelcomeView(hasSeenWelcome: $hasSeenWelcome)
                                .interactiveDismissDisabled()
                        }
                    #endif
                }
                .environment(\.locale, appLocale)
                .onAppear {
                    AppLanguage.applySelection(appLanguage)
                }
                .onChange(of: appLanguage) { newValue in
                    AppLanguage.applySelection(newValue)
                }
            }
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1100, height: 700)
        .commands {
            VVTermCommands()
        }
        #endif
    }
}

// MARK: - macOS App Delegate

#if os(macOS)
struct VVTermCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.openTerminalTab) private var openTerminalTab
    @FocusedValue(\.openLocalSSHDiscovery) private var openLocalSSHDiscovery
    @FocusedValue(\.terminalSplitActions) private var terminalSplitActions

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About VVTerm") {
                AboutWindowController.shared.show()
            }
        }

        CommandGroup(replacing: .newItem) {
            Button("New Window") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut("n", modifiers: .command)

            Divider()

            Button("New Tab") {
                openTerminalTab?()
            }
            .keyboardShortcut("t", modifiers: .command)
            .disabled(openTerminalTab == nil)

            Button(String(localized: "Discover Local Devices...")) {
                openLocalSSHDiscovery?()
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
            .disabled(openLocalSSHDiscovery == nil)

            Button("Close Tab") {
                terminalSplitActions?.closePane()
            }
            .keyboardShortcut("w", modifiers: .command)
            .disabled(terminalSplitActions == nil)
        }

        CommandGroup(replacing: .appSettings) {
            Button("Settings...") {
                SettingsWindowManager.shared.show()
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        CommandGroup(after: .windowArrangement) {
            Button("Previous Tab") {
                ConnectionSessionManager.shared.selectPreviousSession()
            }
            .keyboardShortcut("[", modifiers: [.command, .shift])

            Button("Next Tab") {
                ConnectionSessionManager.shared.selectNextSession()
            }
            .keyboardShortcut("]", modifiers: [.command, .shift])
        }

        // Split commands (Pro feature)
        SplitCommands()
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {



    func applicationDidResignActive(_ notification: Notification) {
        Task { @MainActor in
            AppLockManager.shared.lockIfNeededForBackground()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Close all connections synchronously to ensure cleanup before exit
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            ConnectionSessionManager.shared.disconnectAll()
            semaphore.signal()
        }
        // Wait up to 2 seconds for cleanup
        _ = semaphore.wait(timeout: .now() + 2)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false // Keep running in menu bar
    }

}
#else
// MARK: - iOS App Delegate

class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        return true
    }



    func applicationWillTerminate(_ application: UIApplication) {
        // Close all connections synchronously to ensure cleanup before exit
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            ConnectionSessionManager.shared.disconnectAll()
            semaphore.signal()
        }
        // Wait up to 2 seconds for cleanup
        _ = semaphore.wait(timeout: .now() + 2)
    }

    // Handle app going to background - suspend connections to save resources
    func applicationDidEnterBackground(_ application: UIApplication) {
        Task { @MainActor in
            ConnectionSessionManager.shared.suspendAllForBackground()
            AppLockManager.shared.lockIfNeededForBackground()
        }
    }
}
#endif
