import SwiftUI

struct SidebarFocusReport: ViewModifier {
    let row: String
    let isFocused: Bool

    @Environment(SidebarFocusWatch.self) private var watch: SidebarFocusWatch?
    @State private var instance = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear { watch?.update(instance, row: row, isFocused: isFocused) }
            .onChange(of: isFocused) { watch?.update(instance, row: row, isFocused: isFocused) }
            .onDisappear { watch?.remove(instance) }
    }
}
