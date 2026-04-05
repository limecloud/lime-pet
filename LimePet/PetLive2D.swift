import Foundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

private func petLive2DDebugLog(_ message: String) {
    let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
    let url = URL(fileURLWithPath: "/tmp/limepet-live2d.log")
    if let data = line.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: url.path) {
            if let handle = try? FileHandle(forWritingTo: url) {
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                try? handle.close()
            }
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }
}

enum PetRendererKind: String, Codable, Hashable {
    case sprite
    case live2d
}

struct PetLive2DMotion: Codable, Hashable {
    let group: String
    let index: Int
}

struct PetLive2DStateAction: Codable, Hashable {
    let expression: String?
    let motion: PetLive2DMotion?
}

struct PetLive2DStateActions: Codable, Hashable {
    let idle: PetLive2DStateAction?
    let walking: PetLive2DStateAction?
    let thinking: PetLive2DStateAction?
    let done: PetLive2DStateAction?

    static let empty = PetLive2DStateActions(
        idle: nil,
        walking: nil,
        thinking: nil,
        done: nil
    )
}

struct PetLive2DTapActions: Codable, Hashable {
    let single: PetLive2DMotion?
    let double: PetLive2DMotion?
    let triple: PetLive2DMotion?

    static let empty = PetLive2DTapActions(
        single: nil,
        double: nil,
        triple: nil
    )
}

enum PetLive2DLayoutMode: String, Codable, Hashable {
    case contain
    case manual
}

struct PetLive2DStageStyle: Codable, Hashable {
    let width: Double?
    let height: Double?

    var jsonObject: [String: Double] {
        var object: [String: Double] = [:]
        if let width {
            object["width"] = width
        }
        if let height {
            object["height"] = height
        }
        return object
    }
}

struct PetLive2DConfiguration: Codable, Hashable {
    let modelPath: String
    let modelPaths: [String]?
    let layoutMode: PetLive2DLayoutMode
    let scale: Double
    let offsetX: Double
    let offsetY: Double
    let positionX: Double?
    let positionY: Double?
    let anchorX: Double?
    let anchorY: Double?
    let stageStyle: PetLive2DStageStyle?
    let emotionMap: [String: Int]
    let emotionActions: [String: PetLive2DStateAction]?
    let stateActions: PetLive2DStateActions
    let tapActions: PetLive2DTapActions

    private enum CodingKeys: String, CodingKey {
        case modelPath
        case modelPaths
        case layoutMode
        case scale
        case offsetX
        case offsetY
        case positionX
        case positionY
        case anchorX
        case anchorY
        case stageStyle
        case emotionMap
        case emotionActions
        case stateActions
        case tapActions
    }

    init(
        modelPath: String,
        modelPaths: [String]? = nil,
        layoutMode: PetLive2DLayoutMode = .contain,
        scale: Double,
        offsetX: Double,
        offsetY: Double,
        positionX: Double? = nil,
        positionY: Double? = nil,
        anchorX: Double? = nil,
        anchorY: Double? = nil,
        stageStyle: PetLive2DStageStyle? = nil,
        emotionMap: [String: Int],
        emotionActions: [String: PetLive2DStateAction]? = nil,
        stateActions: PetLive2DStateActions,
        tapActions: PetLive2DTapActions
    ) {
        self.modelPath = modelPath
        self.modelPaths = modelPaths
        self.layoutMode = layoutMode
        self.scale = scale
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.positionX = positionX
        self.positionY = positionY
        self.anchorX = anchorX
        self.anchorY = anchorY
        self.stageStyle = stageStyle
        self.emotionMap = emotionMap
        self.emotionActions = emotionActions
        self.stateActions = stateActions
        self.tapActions = tapActions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        modelPath = try container.decode(String.self, forKey: .modelPath)
        modelPaths = try container.decodeIfPresent([String].self, forKey: .modelPaths)
        layoutMode = try container.decodeIfPresent(PetLive2DLayoutMode.self, forKey: .layoutMode) ?? .contain
        scale = try container.decodeIfPresent(Double.self, forKey: .scale) ?? 1
        offsetX = try container.decodeIfPresent(Double.self, forKey: .offsetX) ?? 0
        offsetY = try container.decodeIfPresent(Double.self, forKey: .offsetY) ?? 0
        positionX = try container.decodeIfPresent(Double.self, forKey: .positionX)
        positionY = try container.decodeIfPresent(Double.self, forKey: .positionY)
        anchorX = try container.decodeIfPresent(Double.self, forKey: .anchorX)
        anchorY = try container.decodeIfPresent(Double.self, forKey: .anchorY)
        stageStyle = try container.decodeIfPresent(PetLive2DStageStyle.self, forKey: .stageStyle)
        emotionMap = try container.decodeIfPresent([String: Int].self, forKey: .emotionMap) ?? [:]
        emotionActions = try container.decodeIfPresent([String: PetLive2DStateAction].self, forKey: .emotionActions)
        stateActions = try container.decodeIfPresent(PetLive2DStateActions.self, forKey: .stateActions) ?? .empty
        tapActions = try container.decodeIfPresent(PetLive2DTapActions.self, forKey: .tapActions) ?? .empty
    }

    var availableModelPaths: [String] {
        let candidates = (modelPaths ?? []) + [modelPath]
        var deduplicated: [String] = []
        var seen = Set<String>()
        for candidate in candidates where !candidate.isEmpty {
            if seen.insert(candidate).inserted {
                deduplicated.append(candidate)
            }
        }
        return deduplicated.isEmpty ? [modelPath] : deduplicated
    }

    var wardrobeCount: Int {
        availableModelPaths.count
    }

    var resolvedStageSize: CGSize {
        CGSize(
            width: CGFloat(stageStyle?.width ?? 420),
            height: CGFloat(stageStyle?.height ?? 420)
        )
    }

    var resolvedSceneFrameSize: CGSize {
        let stageSize = resolvedStageSize
        return CGSize(
            width: max(stageSize.width + 214, 568),
            height: max(stageSize.height + 40, 460)
        )
    }

    func resolved(forClothesIndex index: Int) -> PetLive2DConfiguration {
        let paths = availableModelPaths
        let boundedIndex = min(max(index, 0), max(paths.count - 1, 0))

        return PetLive2DConfiguration(
            modelPath: paths[boundedIndex],
            modelPaths: modelPaths,
            layoutMode: layoutMode,
            scale: scale,
            offsetX: offsetX,
            offsetY: offsetY,
            positionX: positionX,
            positionY: positionY,
            anchorX: anchorX,
            anchorY: anchorY,
            stageStyle: stageStyle,
            emotionMap: emotionMap,
            emotionActions: emotionActions,
            stateActions: stateActions,
            tapActions: tapActions
        )
    }

    func resolvedExpressions(from rawValues: [CompanionLive2DExpressionValue]) -> [Int] {
        rawValues.compactMap { value in
            switch value {
            case .index(let index):
                return index
            case .tag(let tag):
                return emotionMap[tag.lowercased()]
            }
        }
    }

    func resolvedExpressions(from tags: [String]) -> [Int] {
        tags.compactMap { emotionMap[$0.lowercased()] }
    }

    func resolvedIncomingAction(
        rawExpressions: [CompanionLive2DExpressionValue],
        emotionTags: [String],
        preferredMotion: PetLive2DMotion?
    ) -> PetLive2DResolvedActionContent? {
        let lowercasedTags = emotionTags.map { $0.lowercased() }
        let resolved = resolvedExpressions(from: rawExpressions) + resolvedExpressions(from: lowercasedTags)
        var expressionIndices: [Int] = []
        var seenIndices = Set<Int>()
        for index in resolved where seenIndices.insert(index).inserted {
            expressionIndices.append(index)
        }

        var motion = preferredMotion
        for tag in lowercasedTags {
            guard let action = emotionActions?[tag] else { continue }

            for index in resolvedExpressions(from: action.expression.map { [$0] } ?? [])
            where seenIndices.insert(index).inserted {
                expressionIndices.append(index)
            }

            if motion == nil {
                motion = action.motion
            }
        }

        let content = PetLive2DResolvedActionContent(
            expressionIndices: expressionIndices,
            motion: motion
        )
        return content.hasEffect ? content : nil
    }

    func resolvedStateAction(for state: PetState) -> PetLive2DResolvedActionContent? {
        let sourceAction: PetLive2DStateAction?
        switch state {
        case .hidden:
            return nil
        case .idle:
            sourceAction = stateActions.idle
        case .walking:
            sourceAction = stateActions.walking
        case .thinking:
            sourceAction = stateActions.thinking
        case .done:
            sourceAction = stateActions.done
        }

        guard let sourceAction else { return nil }
        let content = PetLive2DResolvedActionContent(
            expressionIndices: resolvedExpressions(from: sourceAction.expression.map { [$0] } ?? []),
            motion: sourceAction.motion
        )
        return content.hasEffect ? content : nil
    }
}

struct PetLive2DResolvedActionContent: Hashable {
    let expressionIndices: [Int]
    let motion: PetLive2DMotion?

    var hasEffect: Bool {
        !expressionIndices.isEmpty || motion != nil
    }
}

struct PetLive2DQueuedAction: Hashable {
    let id: Int
    let expressionIndices: [Int]
    let motion: PetLive2DMotion?

    init(id: Int, content: PetLive2DResolvedActionContent) {
        self.id = id
        self.expressionIndices = content.expressionIndices
        self.motion = content.motion
    }
}

enum PetLive2DTapKind {
    case single
    case double
    case triple
}

private enum PetLive2DHostMessageType: String {
    case loadModel = "load-model"
    case unloadModel = "unload-model"
    case setFacing = "set-facing"
    case setHidden = "set-hidden"
    case playAction = "play-action"
}

private let petLive2DBundle: Bundle = {
    #if SWIFT_PACKAGE
    return .module
    #else
    return .main
    #endif
}()

struct PetLive2DHostView: NSViewRepresentable {
    @ObservedObject var sceneModel: PetSceneModel
    let configuration: PetLive2DConfiguration

    final class HostContainerView: NSView {
        let webView: WKWebView

        init(webView: WKWebView) {
            self.webView = webView
            super.init(frame: .zero)
            wantsLayer = true
            layer?.backgroundColor = NSColor.clear.cgColor
            addSubview(webView)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func layout() {
            super.layout()
            webView.frame = bounds
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(bundle: petLive2DBundle)
    }

    func makeNSView(context: Context) -> HostContainerView {
        HostContainerView(webView: context.coordinator.makeWebView())
    }

    func updateNSView(_ containerView: HostContainerView, context: Context) {
        let hidden = sceneModel.state == .hidden || sceneModel.isResting
        context.coordinator.update(
            webView: containerView.webView,
            configuration: configuration,
            facingRight: sceneModel.isFacingRight,
            hidden: hidden,
            queuedAction: sceneModel.live2dQueuedAction
        )
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let bundle: Bundle
        private lazy var schemeHandler = ResourceSchemeHandler(bundle: bundle)
        private var isReady = false
        private var pendingScripts: [String] = []
        private var lastModelSignature: String?
        private var lastFacingRight: Bool?
        private var lastHidden: Bool?
        private var lastActionID: Int?

        init(bundle: Bundle) {
            self.bundle = bundle
            super.init()
        }

        func makeWebView() -> WKWebView {
            let configuration = WKWebViewConfiguration()
            configuration.userContentController = makeUserContentController()
            configuration.setURLSchemeHandler(schemeHandler, forURLScheme: Self.resourceScheme)
            let webView = WKWebView(frame: .zero, configuration: configuration)
            webView.navigationDelegate = self
            webView.setValue(false, forKey: "drawsBackground")
            webView.setValue(NSColor.clear, forKey: "underPageBackgroundColor")
            webView.autoresizingMask = [.width, .height]
            configureScrollViewIfNeeded(for: webView)

            if let indexURL = runtimeIndexURL() {
                NSLog("[PetLive2DHost] load index \(indexURL.absoluteString)")
                petLive2DDebugLog("load index \(indexURL.absoluteString)")
                webView.load(URLRequest(url: indexURL))
            } else {
                NSLog("[PetLive2DHost] missing runtime index")
                petLive2DDebugLog("missing runtime index")
            }

            return webView
        }

        func update(
            webView: WKWebView,
            configuration: PetLive2DConfiguration,
            facingRight: Bool,
            hidden: Bool,
            queuedAction: PetLive2DQueuedAction?
        ) {
            configureScrollViewIfNeeded(for: webView)
            NSLog(
                "[PetLive2DHost] frame=\(NSStringFromRect(webView.frame)) bounds=\(NSStringFromRect(webView.bounds)) visible=\(NSStringFromRect(webView.visibleRect))"
            )
            petLive2DDebugLog(
                "frame=\(NSStringFromRect(webView.frame)) bounds=\(NSStringFromRect(webView.bounds)) visible=\(NSStringFromRect(webView.visibleRect)) hidden=\(hidden) facingRight=\(facingRight)"
            )
            let resolvedModelPath = resolvedModelPath(for: configuration.modelPath)
            let positionX = configuration.positionX ?? 0
            let positionY = configuration.positionY ?? 0
            let anchorX = configuration.anchorX ?? 0
            let anchorY = configuration.anchorY ?? 0
            let stageWidth = configuration.stageStyle?.width ?? 0
            let stageHeight = configuration.stageStyle?.height ?? 0
            let modelSignatureParts = [
                resolvedModelPath,
                configuration.layoutMode.rawValue,
                String(configuration.scale),
                String(configuration.offsetX),
                String(configuration.offsetY),
                String(positionX),
                String(positionY),
                String(anchorX),
                String(anchorY),
                String(stageWidth),
                String(stageHeight)
            ]
            let modelSignature = modelSignatureParts.joined(separator: "|")
            if modelSignature != lastModelSignature {
                lastModelSignature = modelSignature
                var payload: [String: Any] = [
                    "modelPath": resolvedModelPath,
                    "layoutMode": configuration.layoutMode.rawValue,
                    "scale": configuration.scale,
                    "offsetX": configuration.offsetX,
                    "offsetY": configuration.offsetY
                ]
                if let positionX = configuration.positionX {
                    payload["positionX"] = positionX
                }
                if let positionY = configuration.positionY {
                    payload["positionY"] = positionY
                }
                if let anchorX = configuration.anchorX {
                    payload["anchorX"] = anchorX
                }
                if let anchorY = configuration.anchorY {
                    payload["anchorY"] = anchorY
                }
                let stageStyle = configuration.stageStyle?.jsonObject ?? [:]
                if !stageStyle.isEmpty {
                    payload["stageStyle"] = stageStyle
                }
                send(
                    type: .loadModel,
                    payload: payload,
                    to: webView
                )
            }

            if facingRight != lastFacingRight {
                lastFacingRight = facingRight
                send(
                    type: .setFacing,
                    payload: ["facingRight": facingRight],
                    to: webView
                )
            }

            if hidden != lastHidden {
                lastHidden = hidden
                send(
                    type: .setHidden,
                    payload: ["hidden": hidden],
                    to: webView
                )
            }

            if let queuedAction, queuedAction.id != lastActionID {
                lastActionID = queuedAction.id
                var payload: [String: Any] = [
                    "expressionIndices": queuedAction.expressionIndices
                ]
                if let motion = queuedAction.motion {
                    payload["motion"] = [
                        "group": motion.group,
                        "index": motion.index
                    ]
                }
                send(type: .playAction, payload: payload, to: webView)
            }
        }

        private func configureScrollViewIfNeeded(for webView: WKWebView) {
            guard let scrollView = webView.subviews.first(where: { $0 is NSScrollView }) as? NSScrollView else {
                let subviews = webView.subviews.map { String(describing: type(of: $0)) }.joined(separator: ",")
                petLive2DDebugLog("scrollView missing subviews=\(subviews)")
                return
            }

            scrollView.drawsBackground = false
            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = false
            scrollView.borderType = .noBorder
            scrollView.contentView.scroll(to: .zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
            petLive2DDebugLog(
                "scrollView frame=\(NSStringFromRect(scrollView.frame)) bounds=\(NSStringFromRect(scrollView.bounds)) offset=\(NSStringFromPoint(scrollView.contentView.bounds.origin))"
            )
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            NSLog("[PetLive2DHost] didFinish navigation")
            petLive2DDebugLog("didFinish navigation")
            isReady = true
            logViewportMetrics(for: webView, reason: "didFinish")
            for script in pendingScripts {
                webView.evaluateJavaScript(script, completionHandler: nil)
            }
            pendingScripts.removeAll()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            NSLog("[PetLive2DWeb][navigation] \(error.localizedDescription)")
            petLive2DDebugLog("navigation fail \(error.localizedDescription)")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            NSLog("[PetLive2DWeb][provisional] \(error.localizedDescription)")
            petLive2DDebugLog("provisional fail \(error.localizedDescription)")
        }

        private func send(type: PetLive2DHostMessageType, payload: [String: Any], to webView: WKWebView) {
            guard
                JSONSerialization.isValidJSONObject(payload),
                let data = try? JSONSerialization.data(withJSONObject: [
                    "type": type.rawValue,
                    "payload": payload
                ], options: []),
                let json = String(data: data, encoding: .utf8)
            else {
                return
            }

            let script = "window.LimePetLive2D && window.LimePetLive2D.receive(\(json));"
            NSLog("[PetLive2DHost] send \(type.rawValue) ready=\(isReady)")
            petLive2DDebugLog("send \(type.rawValue) ready=\(isReady) payload=\(json)")
            if isReady {
                webView.evaluateJavaScript(script, completionHandler: nil)
            } else {
                pendingScripts.append(script)
            }
        }

        private func logViewportMetrics(for webView: WKWebView, reason: String) {
            let script = """
            (() => JSON.stringify({
              reason: "\(reason)",
              userAgent: navigator.userAgent,
              innerWidth: window.innerWidth,
              innerHeight: window.innerHeight,
              outerWidth: window.outerWidth,
              outerHeight: window.outerHeight,
              devicePixelRatio: window.devicePixelRatio,
              visualViewport: window.visualViewport ? {
                width: window.visualViewport.width,
                height: window.visualViewport.height,
                scale: window.visualViewport.scale,
                offsetLeft: window.visualViewport.offsetLeft,
                offsetTop: window.visualViewport.offsetTop
              } : null,
              documentElement: {
                clientWidth: document.documentElement ? document.documentElement.clientWidth : null,
                clientHeight: document.documentElement ? document.documentElement.clientHeight : null,
                scrollWidth: document.documentElement ? document.documentElement.scrollWidth : null,
                scrollHeight: document.documentElement ? document.documentElement.scrollHeight : null
              },
              body: document.body ? {
                clientWidth: document.body.clientWidth,
                clientHeight: document.body.clientHeight,
                scrollWidth: document.body.scrollWidth,
                scrollHeight: document.body.scrollHeight
              } : null,
              stageRect: (() => {
                const stage = document.getElementById("stage");
                if (!stage) return null;
                const rect = stage.getBoundingClientRect();
                return { x: rect.x, y: rect.y, width: rect.width, height: rect.height };
              })(),
              canvasRect: (() => {
                const canvas = document.getElementById("live2d-canvas");
                if (!canvas) return null;
                const rect = canvas.getBoundingClientRect();
                return { x: rect.x, y: rect.y, width: rect.width, height: rect.height };
              })()
            }))();
            """

            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    petLive2DDebugLog("viewport metrics error \(reason) \(error.localizedDescription)")
                    return
                }

                guard let value = result as? String else {
                    petLive2DDebugLog("viewport metrics empty \(reason)")
                    return
                }

                petLive2DDebugLog("viewport metrics \(value)")
            }
        }

        private func runtimeIndexURL() -> URL? {
            guard let resourcePath = runtimeIndexResourcePath() else {
                return nil
            }

            return URL(string: "\(Self.resourceScheme)://\(Self.resourceHost)/\(resourcePath)")
        }

        private func runtimeIndexResourcePath() -> String? {
            if bundle.url(forResource: "index", withExtension: "html", subdirectory: "live2d-runtime") != nil {
                return "live2d-runtime/index.html"
            }

            if bundle.url(forResource: "index", withExtension: "html") != nil {
                return "index.html"
            }

            return nil
        }

        private func makeUserContentController() -> WKUserContentController {
            let controller = WKUserContentController()
            controller.add(self, name: "live2dLog")
            controller.addUserScript(
                WKUserScript(
                    source: Self.consoleBridgeScript,
                    injectionTime: .atDocumentStart,
                    forMainFrameOnly: true
                )
            )
            return controller
        }

        private func resolvedModelPath(for logicalPath: String) -> String {
            if let directURL = URL(string: logicalPath), directURL.scheme != nil {
                return logicalPath
            }

            if ResourceSchemeHandler.resourceExists(
                relativePath: logicalPath,
                in: PetModelStorage.resourceRoots(bundle: bundle)
            ) {
                return logicalPath
            }

            let nsLogicalPath = logicalPath as NSString
            let fileName = nsLogicalPath.lastPathComponent as NSString
            let resourceName = fileName.deletingPathExtension
            let resourceExtension = fileName.pathExtension.isEmpty ? nil : fileName.pathExtension
            let subdirectory = nsLogicalPath.deletingLastPathComponent

            if !subdirectory.isEmpty,
               bundle.url(
                    forResource: resourceName,
                    withExtension: resourceExtension,
                    subdirectory: subdirectory
               ) != nil {
                return logicalPath
            }

            if bundle.url(forResource: resourceName, withExtension: resourceExtension) != nil {
                return "./\(fileName)"
            }

            return logicalPath
        }

        private static let consoleBridgeScript = """
        (() => {
          const post = (level, values) => {
            try {
              window.webkit.messageHandlers.live2dLog.postMessage({
                level,
                values: values.map((value) => {
                  if (typeof value === "string") {
                    return value;
                  }
                  try {
                    return JSON.stringify(value);
                  } catch (error) {
                    return String(value);
                  }
                })
              });
            } catch (error) {
            }
          };

          for (const level of ["log", "warn", "error"]) {
            const original = console[level];
            console[level] = (...args) => {
              post(level, args);
              original.apply(console, args);
            };
          }

          window.addEventListener("error", (event) => {
            post("error", [event.message || "window error"]);
          });

          window.addEventListener("unhandledrejection", (event) => {
            post("error", ["unhandledrejection", event.reason]);
          });
        })();
        """

        private static let resourceScheme = "limepet"
        private static let resourceHost = "bundle"

        final class ResourceSchemeHandler: NSObject, WKURLSchemeHandler {
            private let rootURLs: [URL]

            init(bundle: Bundle) {
                self.rootURLs = PetModelStorage.resourceRoots(bundle: bundle)
                super.init()
            }

            func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
                guard
                    let requestURL = urlSchemeTask.request.url,
                    requestURL.scheme == Coordinator.resourceScheme,
                    requestURL.host == Coordinator.resourceHost
                else {
                    fail(urlSchemeTask, code: NSURLErrorBadURL, description: "Invalid Live2D resource URL")
                    return
                }

                let relativePath = requestURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                guard let targetURL = Self.resolve(relativePath: relativePath, in: rootURLs),
                      let data = try? Data(contentsOf: targetURL) else {
                    fail(urlSchemeTask, code: NSURLErrorFileDoesNotExist, description: "Missing Live2D resource: \(relativePath)")
                    return
                }

                let response = URLResponse(
                    url: requestURL,
                    mimeType: Self.mimeType(for: targetURL),
                    expectedContentLength: data.count,
                    textEncodingName: Self.textEncodingName(for: targetURL)
                )
                urlSchemeTask.didReceive(response)
                urlSchemeTask.didReceive(data)
                urlSchemeTask.didFinish()
            }

            func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
            }

            private func fail(_ task: any WKURLSchemeTask, code: Int, description: String) {
                task.didFailWithError(
                    NSError(
                        domain: NSURLErrorDomain,
                        code: code,
                        userInfo: [NSLocalizedDescriptionKey: description]
                    )
                )
            }

            private static func mimeType(for url: URL) -> String {
                if let type = UTType(filenameExtension: url.pathExtension),
                   let mimeType = type.preferredMIMEType {
                    return mimeType
                }

                switch url.pathExtension.lowercased() {
                case "moc3":
                    return "application/octet-stream"
                default:
                    return "application/octet-stream"
                }
            }

            private static func textEncodingName(for url: URL) -> String? {
                switch url.pathExtension.lowercased() {
                case "html", "js", "json", "css", "txt":
                    return "utf-8"
                default:
                    return nil
                }
            }

            static func resourceExists(relativePath: String, in rootURLs: [URL]) -> Bool {
                resolve(relativePath: relativePath, in: rootURLs) != nil
            }

            private static func resolve(relativePath: String, in rootURLs: [URL]) -> URL? {
                for rootURL in rootURLs {
                    let targetURL = PetURLBuilder.appendingPath(relativePath, to: rootURL).standardizedFileURL
                    guard targetURL.path.hasPrefix(rootURL.path) else {
                        continue
                    }
                    if FileManager.default.fileExists(atPath: targetURL.path) {
                        return targetURL
                    }
                }
                return nil
            }
        }
    }
}

extension PetLive2DHostView.Coordinator: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard
            message.name == "live2dLog",
            let body = message.body as? [String: Any],
            let level = body["level"] as? String
        else {
            return
        }

        let values = (body["values"] as? [String]) ?? []
        NSLog("[PetLive2DWeb][\(level)] \(values.joined(separator: " | "))")
        petLive2DDebugLog("[\(level)] \(values.joined(separator: " | "))")
    }
}
