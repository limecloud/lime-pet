(function () {
  const stage = document.getElementById("stage");
  const canvas = document.getElementById("live2d-canvas");
  const status = document.getElementById("status");

  const state = {
    app: null,
    model: null,
    config: null,
    facingRight: true,
    hidden: false,
    pendingAction: null,
    statusTimer: null,
    resizeObserver: null,
    loadingToken: 0
  };
  const modelLoadTimeoutMs = 15000;

  window.__LIME_PET_RUNTIME__ = {
    getMetrics() {
      if (!state.model || !state.config) {
        return null;
      }

      const localBounds = state.model.getLocalBounds();
      const globalBounds = state.model.getBounds();
      return {
        config: state.config,
        canvas: {
          width: canvas.width,
          height: canvas.height
        },
        localBounds: {
          x: localBounds.x,
          y: localBounds.y,
          width: localBounds.width,
          height: localBounds.height
        },
        globalBounds: {
          x: globalBounds.x,
          y: globalBounds.y,
          width: globalBounds.width,
          height: globalBounds.height
        },
        position: {
          x: state.model.x,
          y: state.model.y
        },
        scale: {
          x: state.model.scale.x,
          y: state.model.scale.y
        }
      };
    }
  };

  function ensureApp() {
    if (state.app) {
      return state.app;
    }

    state.app = new PIXI.Application({
      view: canvas,
      transparent: true,
      backgroundAlpha: 0,
      antialias: true,
      autoStart: true,
      resizeTo: stage
    });

    if (typeof ResizeObserver === "function") {
      state.resizeObserver = new ResizeObserver(() => {
        layoutModel();
      });
      state.resizeObserver.observe(stage);
    } else {
      window.addEventListener("resize", layoutModel);
    }

    return state.app;
  }

  function showStatus(text) {
    if (state.statusTimer !== null) {
      window.clearTimeout(state.statusTimer);
      state.statusTimer = null;
    }

    if (!text) {
      status.textContent = "";
      status.classList.remove("visible");
      return;
    }

    status.textContent = text;
    status.classList.add("visible");
    state.statusTimer = window.setTimeout(() => {
      status.classList.remove("visible");
      state.statusTimer = null;
    }, 2200);
  }

  function sendHostEvent(type, payload = {}) {
    try {
      window.parent?.postMessage(
        {
          source: "lime-pet-live2d",
          type,
          payload
        },
        "*",
      );
    } catch (error) {
      console.warn("[LimePetLive2D] Failed to post host event", type, error);
    }
  }

  function detectModelFormat(modelPath) {
    const normalizedPath = String(modelPath || "").toLowerCase();
    return normalizedPath.endsWith(".model3.json") ? "cubism4" : "cubism2";
  }

  function resolveModelPath(modelPath) {
    if (
      modelPath.startsWith("./") ||
      modelPath.startsWith("../") ||
      modelPath.startsWith("http://") ||
      modelPath.startsWith("https://") ||
      modelPath.startsWith("file:")
    ) {
      return modelPath;
    }

    return `../${modelPath.replace(/^\/+/, "")}`;
  }

  function resolveMotionGroups(model) {
    const candidates = [
      model?.internalModel?.motionManager?.motionGroups,
      model?.internalModel?.settings?.motions,
      model?.internalModel?.motionManager?._groups
    ];

    for (const candidate of candidates) {
      if (candidate && typeof candidate === "object") {
        return Object.keys(candidate);
      }
    }

    return [];
  }

  function resolveExpressionCount(model) {
    const candidates = [
      model?.internalModel?.expressionManager?.definitions,
      model?.internalModel?.settings?.expressions
    ];

    for (const candidate of candidates) {
      if (Array.isArray(candidate)) {
        return candidate.length;
      }
    }

    return 0;
  }

  function unloadModel() {
    if (!state.app || !state.model) {
      state.model = null;
      state.config = null;
      return;
    }

    state.app.stage.removeChild(state.model);
    state.model.destroy();
    state.model = null;
    state.config = null;
    sendHostEvent("model-unloaded");
  }

  function applyFacing() {
    canvas.style.transformOrigin = "center center";
    canvas.style.transform = state.facingRight ? "none" : "scaleX(-1)";
  }

  function applyHidden() {
    canvas.style.opacity = state.hidden ? "0" : "1";
  }

  function numericOrNull(value) {
    return typeof value === "number" && Number.isFinite(value) ? value : null;
  }

  function layoutModel() {
    if (!state.model || !state.config) {
      return;
    }

    const stageWidth = Math.max(stage.clientWidth, 1);
    const stageHeight = Math.max(stage.clientHeight, 1);
    const layoutMode = state.config.layoutMode === "manual" ? "manual" : "contain";

    if (layoutMode === "manual") {
      const manualScale = numericOrNull(state.config.scale) ?? 1;
      const positionX = numericOrNull(state.config.positionX) ?? 0;
      const positionY = numericOrNull(state.config.positionY) ?? 0;
      const anchorX = numericOrNull(state.config.anchorX);
      const anchorY = numericOrNull(state.config.anchorY);

      if (state.model.anchor && typeof state.model.anchor.set === "function") {
        state.model.anchor.set(anchorX ?? state.model.anchor.x ?? 0, anchorY ?? state.model.anchor.y ?? 0);
      }

      state.model.scale.set(manualScale, manualScale);
      state.model.x = positionX;
      state.model.y = positionY;
      applyFacing();
      return;
    }

    const paddingX = stageWidth * 0.06;
    const paddingTop = stageHeight * 0.04;
    const paddingBottom = stageHeight * 0.02;
    const safeWidth = Math.max(stageWidth - paddingX * 2, 1);
    const safeHeight = Math.max(stageHeight - paddingTop - paddingBottom, 1);
    const bounds = state.model.getLocalBounds();
    const naturalWidth = Math.max(bounds.width, 1);
    const naturalHeight = Math.max(bounds.height, 1);
    const fitScale = Math.min(
      safeWidth / naturalWidth,
      safeHeight / naturalHeight
    );
    const baseScale = fitScale * state.config.scale;
    let resolvedScale = Number.isFinite(baseScale) && baseScale > 0 ? baseScale : fitScale;

    function measureBoundsAtScale(scale) {
      state.model.scale.set(scale, scale);
      state.model.x = 0;
      state.model.y = 0;
      return state.model.getBounds();
    }

    function placeModel(globalBounds) {
      const centeredX = stageWidth * 0.5 - (globalBounds.x + globalBounds.width * 0.5);
      const groundedY = stageHeight - paddingBottom - globalBounds.bottom;
      state.model.scale.set(resolvedScale, resolvedScale);
      state.model.x = centeredX + state.config.offsetX;
      state.model.y = groundedY + state.config.offsetY;
    }

    let globalBounds = measureBoundsAtScale(resolvedScale);
    const widthCorrection = safeWidth / Math.max(globalBounds.width, 1);
    const heightCorrection = safeHeight / Math.max(globalBounds.height, 1);
    const correction = Math.min(widthCorrection, heightCorrection, 1);

    if (Number.isFinite(correction) && correction > 0 && correction < 1) {
      resolvedScale *= correction;
      globalBounds = measureBoundsAtScale(resolvedScale);
    }

    placeModel(globalBounds);
    globalBounds = state.model.getBounds();

    if (globalBounds.top < paddingTop) {
      state.model.y += paddingTop - globalBounds.top;
      globalBounds = state.model.getBounds();
    }

    if (globalBounds.bottom > stageHeight - paddingBottom) {
      state.model.y -= globalBounds.bottom - (stageHeight - paddingBottom);
      globalBounds = state.model.getBounds();
    }

    if (globalBounds.left < paddingX) {
      state.model.x += paddingX - globalBounds.left;
      globalBounds = state.model.getBounds();
    }

    if (globalBounds.right > stageWidth - paddingX) {
      state.model.x -= globalBounds.right - (stageWidth - paddingX);
    }

    applyFacing();
  }

  async function playAction(payload) {
    if (!payload) {
      return;
    }

    if (!state.model) {
      state.pendingAction = payload;
      return;
    }

    if (Array.isArray(payload.expressionIndices)) {
      for (const expressionIndex of payload.expressionIndices) {
        try {
          await state.model.expression(expressionIndex);
        } catch (error) {
          console.warn("[LimePetLive2D] Failed to apply expression", expressionIndex, error);
        }
      }
    }

    if (payload.motion && typeof payload.motion.index === "number") {
      try {
        await state.model.motion(payload.motion.group ?? "", payload.motion.index);
      } catch (error) {
        console.warn("[LimePetLive2D] Failed to play motion", payload.motion, error);
      }
    }
  }

  async function loadModel(config) {
    ensureApp();
    state.loadingToken += 1;
    const currentToken = state.loadingToken;
    const format = detectModelFormat(config.modelPath);

    sendHostEvent("model-loading", {
      modelPath: config.modelPath,
      format
    });
    showStatus(format === "cubism4" ? "正在加载 Cubism 4/5 模型" : "正在加载 Cubism 2 模型");

    try {
      let timedOut = false;
      let timeoutId = null;
      const modelPromise = PIXI.live2d.Live2DModel.from(resolveModelPath(config.modelPath)).then((model) => {
        if (timedOut) {
          model.destroy();
        }
        return model;
      });
      const timeoutPromise = new Promise((_, reject) => {
        timeoutId = window.setTimeout(() => {
          timedOut = true;
          reject(new Error(`Live2D model load timed out after ${modelLoadTimeoutMs}ms`));
        }, modelLoadTimeoutMs);
      });
      const model = await Promise.race([modelPromise, timeoutPromise]).finally(() => {
        if (timeoutId !== null) {
          window.clearTimeout(timeoutId);
        }
      });
      if (currentToken !== state.loadingToken) {
        model.destroy();
        return;
      }

      unloadModel();
      state.config = config;
      state.model = model;
      state.model.interactive = false;
      state.app.stage.addChild(state.model);
      layoutModel();
      applyHidden();

      const motionGroups = resolveMotionGroups(model);
      const expressionCount = resolveExpressionCount(model);
      sendHostEvent("model-loaded", {
        modelPath: config.modelPath,
        format,
        motionGroups,
        expressionCount,
        metrics: window.__LIME_PET_RUNTIME__.getMetrics()
      });
      console.log("[LimePetLive2D] model metrics", window.__LIME_PET_RUNTIME__.getMetrics());
      showStatus("Live2D 模型已就绪");

      if (state.pendingAction) {
        const queuedAction = state.pendingAction;
        state.pendingAction = null;
        await playAction(queuedAction);
      }
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      console.error("[LimePetLive2D] Failed to load model", error);
      showStatus("Live2D 模型加载失败");
      sendHostEvent("model-error", {
        modelPath: config.modelPath,
        format,
        message
      });
    }
  }

  function handleMessage(rawMessage) {
    const message = typeof rawMessage === "string" ? JSON.parse(rawMessage) : rawMessage;
    if (!message || typeof message.type !== "string") {
      return;
    }

    switch (message.type) {
      case "load-model":
        void loadModel(message.payload || {});
        break;
      case "unload-model":
        unloadModel();
        break;
      case "set-facing":
        state.facingRight = message.payload?.facingRight !== false;
        applyFacing();
        break;
      case "set-hidden":
        state.hidden = message.payload?.hidden === true;
        applyHidden();
        break;
      case "play-action":
        void playAction(message.payload || {});
        break;
      default:
        break;
    }
  }

  ensureApp();
  applyHidden();

  window.LimePetLive2D = {
    receive(message) {
      try {
        handleMessage(message);
      } catch (error) {
        console.error("[LimePetLive2D] Unhandled message error", error);
      }
    }
  };

  window.addEventListener("message", (event) => {
    try {
      handleMessage(event.data);
    } catch (error) {
      console.error("[LimePetLive2D] Failed to handle postMessage", error);
    }
  });
})();
