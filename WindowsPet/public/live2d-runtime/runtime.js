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

  function resolveModelPath(modelPath) {
    if (
      modelPath.startsWith("../") ||
      modelPath.startsWith("http://") ||
      modelPath.startsWith("https://") ||
      modelPath.startsWith("file:")
    ) {
      return modelPath;
    }

    return `../${modelPath.replace(/^\/+/, "")}`;
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
  }

  function applyFacing() {
    if (!state.model) {
      return;
    }

    const magnitude = Math.abs(state.model.scale.x || 1);
    state.model.scale.x = state.facingRight ? magnitude : -magnitude;
  }

  function applyHidden() {
    canvas.style.opacity = state.hidden ? "0" : "1";
  }

  function layoutModel() {
    if (!state.model || !state.config) {
      return;
    }

    const stageWidth = Math.max(stage.clientWidth, 1);
    const stageHeight = Math.max(stage.clientHeight, 1);
    const naturalHeight = Math.max(state.model.height, 1);
    const baseScale = (stageHeight * 0.76 / naturalHeight) * state.config.scale;
    const resolvedScale = Number.isFinite(baseScale) && baseScale > 0 ? baseScale : 1;

    state.model.scale.set(resolvedScale, resolvedScale);
    applyFacing();
    state.model.x = stageWidth * 0.5 + state.config.offsetX;
    state.model.y = stageHeight * 0.78 + state.config.offsetY;
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

    try {
      const model = await PIXI.live2d.Live2DModel.from(resolveModelPath(config.modelPath));
      if (currentToken !== state.loadingToken) {
        model.destroy();
        return;
      }

      unloadModel();
      state.config = config;
      state.model = model;
      state.model.anchor.set(0.5, 0.5);
      state.model.interactive = false;
      state.app.stage.addChild(state.model);
      layoutModel();
      applyHidden();

      if (state.pendingAction) {
        const queuedAction = state.pendingAction;
        state.pendingAction = null;
        await playAction(queuedAction);
      }
    } catch (error) {
      console.error("[LimePetLive2D] Failed to load model", error);
      showStatus("Live2D 模型加载失败");
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
