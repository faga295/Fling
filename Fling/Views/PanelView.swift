import SwiftUI

// MARK: - Panel View Model

class PanelViewModel: ObservableObject {
    @Published var highlightedAction: WindowAction?
}

// MARK: - Panel View

struct PanelView: View {
    @ObservedObject var viewModel: PanelViewModel

    private let cellSize: CGFloat = 72
    private let spacing: CGFloat = 4

    var body: some View {
        VStack(spacing: spacing) {
            // Top: Up (k)
            HStack(spacing: spacing) {
                Color.clear.frame(width: cellSize, height: cellSize)
                actionCell(.top)
                Color.clear.frame(width: cellSize, height: cellSize)
            }

            // Middle: Left (h) + Center (space) + Right (l)
            HStack(spacing: spacing) {
                actionCell(.left)
                actionCell(.maximize)
                actionCell(.right)
            }

            // Bottom: Down (j)
            HStack(spacing: spacing) {
                Color.clear.frame(width: cellSize, height: cellSize)
                actionCell(.bottom)
                Color.clear.frame(width: cellSize, height: cellSize)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.3), radius: 20, y: 5)
        )
    }

    @ViewBuilder
    private func actionCell(_ action: WindowAction) -> some View {
        let isHighlighted = viewModel.highlightedAction == action

        VStack(spacing: 4) {
            Image(systemName: action.iconName)
                .font(.system(size: 28, weight: .medium))
                .foregroundColor(isHighlighted ? .white : .primary)

            Text(action.keyLabel)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(isHighlighted ? .white.opacity(0.8) : .secondary)
        }
        .frame(width: cellSize, height: cellSize)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isHighlighted ? Color.accentColor : Color.primary.opacity(0.06))
        )
        .animation(.easeOut(duration: 0.1), value: isHighlighted)
    }
}
