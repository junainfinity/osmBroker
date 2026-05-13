import Foundation

/// Four top-level tabs. Order is the user's mental model:
///  1. CLI — what's installed on this Mac
///  2. Models — pick which ones to serve
///  3. Serve — start/stop the API server
///  4. More — discover + install other CLIs
enum Pane: String, CaseIterable, Identifiable {
    case cli, models, serve, more
    var id: String { rawValue }

    var sidebarTitle: String {
        switch self {
        case .cli:    return "CLI"
        case .models: return "Models"
        case .serve:  return "Serve"
        case .more:   return "More"
        }
    }

    var sidebarIcon: String {
        switch self {
        case .cli:    return "terminal"
        case .models: return "rectangle.stack"
        case .serve:  return "antenna.radiowaves.left.and.right"
        case .more:   return "square.grid.2x2"
        }
    }
}
