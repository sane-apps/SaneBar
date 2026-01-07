import SwiftUI

/// Warning shown when separator is positioned incorrectly
struct PositionWarningView: View {
    var errorType: MenuBarManager.PositionError?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .font(.title2)
                Text(titleText)
                    .font(.headline)
            }

            Text(descriptionText)
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                Image(systemName: "command")
                    .font(.caption)
                Text(instructionText)
                Image(systemName: separatorIcon)
                    .font(.caption)
            }
            .font(.callout)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var titleText: String {
        switch errorType {
        case .separatorRightOfMain:
            return "Separator Misplaced"
        case .alwaysHiddenRightOfSeparator:
            return "Separators Out of Order"
        case .separatorsOverlapping, .none:
            return "Separators Lost"
        }
    }

    private var descriptionText: AttributedString {
        switch errorType {
        case .separatorRightOfMain:
            return (try? AttributedString(
                markdown: "The **/** separator is to the right of the main icon. Hiding would push everything off screen!"
            )) ?? AttributedString("The / separator is to the right of the main icon.")
        case .alwaysHiddenRightOfSeparator:
            return (try? AttributedString(
                markdown: "The two **/** separators are in the wrong order. The lighter one should be to the left."
            )) ?? AttributedString("The two / separators are in the wrong order.")
        case .separatorsOverlapping, .none:
            return (try? AttributedString(
                markdown: "The **/** separators are overlapping or off-screen. Please reposition them."
            )) ?? AttributedString("The / separators are overlapping.")
        }
    }

    private var instructionText: AttributedString {
        switch errorType {
        case .separatorRightOfMain:
            return (try? AttributedString(markdown: "**⌘+drag** the **/** back to the left of")) ?? AttributedString("Cmd+drag the / back to the left")
        case .alwaysHiddenRightOfSeparator:
            return (try? AttributedString(markdown: "**⌘+drag** the lighter **/** to the left of the brighter")) ?? AttributedString("Cmd+drag the lighter / to the left")
        case .separatorsOverlapping, .none:
            return (try? AttributedString(markdown: "**⌘+drag** each **/** to separate them")) ?? AttributedString("Cmd+drag each / to separate them")
        }
    }

    private var separatorIcon: String {
        switch errorType {
        case .separatorRightOfMain:
            return "line.3.horizontal.decrease.circle"
        case .alwaysHiddenRightOfSeparator, .separatorsOverlapping, .none:
            return "line.diagonal"
        }
    }
}

#Preview("Separator Right of Main") {
    PositionWarningView(errorType: .separatorRightOfMain)
        .frame(width: 300)
}

#Preview("Separators Wrong Order") {
    PositionWarningView(errorType: .alwaysHiddenRightOfSeparator)
        .frame(width: 300)
}

#Preview("Separators Overlapping") {
    PositionWarningView(errorType: .separatorsOverlapping)
        .frame(width: 300)
}
