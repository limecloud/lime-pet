import SwiftUI

struct PetRenderSurface: View {
    @ObservedObject var sceneModel: PetSceneModel
    let palette: PetRenderPalette

    var body: some View {
        Group {
            if sceneModel.character.rendererKind == .live2d, let configuration = sceneModel.character.live2d {
                PetLive2DHostView(sceneModel: sceneModel, configuration: configuration)
                    .allowsHitTesting(false)
            } else {
                PetCharacterRenderer(sceneModel: sceneModel, palette: palette)
            }
        }
        .frame(width: 156, height: 176)
    }
}
