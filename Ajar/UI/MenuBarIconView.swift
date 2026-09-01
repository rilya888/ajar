import SwiftUI

/// The only thing most users ever see. SF Symbol, template rendering, so the menu bar
/// theme is not our problem.
struct MenuBarIconView: View {
    let model: MenuBarViewModel

    var body: some View {
        Image(systemName: model.symbolName)
            .opacity(model.isDimmed ? 0.45 : 1)
    }
}
