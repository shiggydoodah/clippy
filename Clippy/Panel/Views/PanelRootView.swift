import SwiftUI

struct PanelRootView: View {
    @Bindable var model: PanelViewModel

    var body: some View {
        VStack(spacing: 0) {
            SearchFieldView(model: model)
            Divider()
            TabBarView(model: model)
            Divider()
            HStack(spacing: 0) {
                ItemListView(model: model)
                    .frame(width: 390)
                Divider()
                PreviewPaneView(model: model)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: .infinity)
            Divider()
            FooterBarView(model: model)
        }
        .frame(width: PanelController.panelSize.width, height: PanelController.panelSize.height)
    }
}
