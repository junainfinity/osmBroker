import SwiftUI
import osmBrokerCore

// MARK: - Pane head (eyebrow / title / lede / toolbar)
// Shared by CLIPane, ModelsPane, ServePane, MorePane.

struct PaneHead<Toolbar: View>: View {
    let eyebrow: String
    let title: String
    let lede: String
    @ViewBuilder var toolbar: () -> Toolbar

    var body: some View {
        HStack(alignment: .bottom, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(text: eyebrow)
                DisplayTitle(text: title)
                Lede(text: lede)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ToolbarGroup { toolbar() }
        }
    }
}

// MARK: - Broker error banner
// Shown in CLI + Serve panes when `state.brokerError != nil`.

struct BrokerErrorBanner: View {
    @EnvironmentObject private var state: AppState
    let message: String
    let suggestion: Int?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.Palette.amber)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 6) {
                Text("Broker failed to start")
                    .font(Theme.Typeface.body(13, weight: .semibold))
                    .foregroundStyle(Theme.Palette.fg)
                Text(message)
                    .font(Theme.Typeface.body(12))
                    .foregroundStyle(Theme.Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if let s = suggestion {
                    HStack(spacing: 8) {
                        SecondaryButton(title: "Use port \(s)") {
                            state.port = String(s)
                            Task { await state.startBroker() }
                        }
                        Spacer()
                    }
                    .padding(.top, 2)
                }
            }
            Spacer()
        }
        .padding(14)
        .background(Theme.Palette.accentSoft.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.chunk, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.chunk, style: .continuous)
                .strokeBorder(Theme.Palette.amber.opacity(0.4), lineWidth: 1)
        }
    }
}

// MARK: - Path prettifier (collapses $HOME → ~)
// Used wherever we show a binary path so the dark JSON / pill rows don't
// wrap on long absolute paths.

func prettyHomePath(_ path: String) -> String {
    let home = NSHomeDirectory()
    if path.hasPrefix(home) { return "~" + path.dropFirst(home.count) }
    return path
}

// MARK: - WrapHStack + FlowLayout
// Lightweight reflowing horizontal stack. Used for pill rows that need to
// wrap when their parent narrows.

struct WrapHStack<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        FlowLayout(spacing: spacing) { content() }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var widestRow: CGFloat = 0
        var firstInRow = true

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            let needsSpace = firstInRow ? size.width : (rowWidth + spacing + size.width)
            if needsSpace > maxWidth, !firstInRow {
                totalHeight += rowHeight + spacing
                widestRow = max(widestRow, rowWidth)
                rowWidth = size.width
                rowHeight = size.height
                firstInRow = false
            } else {
                rowWidth = firstInRow ? size.width : rowWidth + spacing + size.width
                rowHeight = max(rowHeight, size.height)
                firstInRow = false
            }
        }
        totalHeight += rowHeight
        widestRow = max(widestRow, rowWidth)
        return CGSize(width: maxWidth.isFinite ? maxWidth : widestRow, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0
        var firstInRow = true

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            let candidateX = firstInRow ? x : x + spacing
            if (candidateX - bounds.minX) + size.width > maxWidth, !firstInRow {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
                firstInRow = true
            }
            let placeX = firstInRow ? x : x + spacing
            sub.place(at: CGPoint(x: placeX, y: y), proposal: ProposedViewSize(size))
            x = placeX + size.width
            rowHeight = max(rowHeight, size.height)
            firstInRow = false
        }
    }
}
