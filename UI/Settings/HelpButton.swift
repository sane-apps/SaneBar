import SwiftUI

struct HelpButton: View {
    let tip: String
    @State private var isShowingPopover = false

    var body: some View {
        Button {
            isShowingPopover.toggle()
        } label: {
            Image(systemName: "questionmark.circle")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .popover(isPresented: $isShowingPopover) {
            Text(tip)
                .font(.system(size: 13))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding()
                .frame(width: 300)
        }
    }
}
