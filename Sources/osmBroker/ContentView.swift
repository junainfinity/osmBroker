import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var state: AppState
    /// Persists across launches via UserDefaults under `osmBroker.theme`.
    /// See [[Dark-Mode]].
    @AppStorage("osmBroker.theme") private var themeRaw: String = AppTheme.system.rawValue

    private var theme: AppTheme {
        AppTheme(rawValue: themeRaw) ?? .system
    }

    var body: some View {
        // No more top bar VStack — see [[Top-Space-Removal]].
        // Sidebar pads its own top so the brand row clears the OS traffic
        // lights; the main pane's `.padding(28)` is enough since the lights
        // are far to the left.
        HStack(spacing: 0) {
            Sidebar()
                .frame(width: 240)
            Divider().overlay(Theme.Palette.borderStrong)
            MainPane()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.Palette.surface)
        .preferredColorScheme(theme.preferredScheme)
        .task {
            await state.refreshDetection()
        }
    }
}

private struct MainPane: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ZStack {
            Theme.Palette.background.ignoresSafeArea()
            Group {
                switch state.selectedPane {
                case .cli:    CLIPane()
                case .models: ModelsPane()
                case .serve:  ServePane()
                case .more:   MorePane()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
