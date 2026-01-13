import SwiftUI

/// Warning shown when separator is positioned incorrectly
struct PositionWarningView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .font(.title2)
                Text("Separator Misplaced")
                    .font(.headline)
            }

            Text("The separator is in the wrong position. Hiding would push icons off screen.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                Text("**⌘+drag** the separator left of")
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.callout)
            }
            .font(.callout)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    PositionWarningView()
        .frame(width: 300)
}
