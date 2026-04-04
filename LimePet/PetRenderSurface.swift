import SwiftUI

struct PetRenderSurface: View {
    @ObservedObject var sceneModel: PetSceneModel
    let palette: PetRenderPalette

    private var surfaceSize: CGSize {
        if sceneModel.character.rendererKind == .live2d,
           let configuration = sceneModel.resolvedLive2DConfiguration {
            return configuration.resolvedStageSize
        }

        return CGSize(width: 156, height: 176)
    }

    var body: some View {
        Group {
            if sceneModel.character.rendererKind == .live2d,
               let configuration = sceneModel.resolvedLive2DConfiguration {
                PetLive2DHostView(sceneModel: sceneModel, configuration: configuration)
                    .allowsHitTesting(false)
            } else {
                PetCharacterRenderer(sceneModel: sceneModel, palette: palette)
            }
        }
        .frame(width: surfaceSize.width, height: surfaceSize.height)
    }
}
