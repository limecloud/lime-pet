import type { PetLive2DConfiguration, PetLive2DHostAction } from "./characterLibrary";

interface HostMessage {
  type: string;
  payload: Record<string, unknown>;
}

export class Live2DFrameDriver {
  private readonly frame: HTMLIFrameElement;
  private frameLoaded = false;
  private pendingMessages: HostMessage[] = [];

  constructor(frame: HTMLIFrameElement) {
    this.frame = frame;
    this.frame.addEventListener("load", () => {
      this.frameLoaded = true;
      this.flushPendingMessages();
    });
  }

  setSource(source: string): void {
    if (this.frame.src === source) {
      return;
    }

    this.frameLoaded = false;
    this.frame.src = source;
  }

  loadModel(configuration: PetLive2DConfiguration): void {
    const payload: Record<string, unknown> = {
      modelPath: configuration.modelPath,
      layoutMode: configuration.layoutMode ?? "contain",
      scale: configuration.scale,
      offsetX: configuration.offsetX,
      offsetY: configuration.offsetY
    };

    if (typeof configuration.positionX === "number") {
      payload.positionX = configuration.positionX;
    }
    if (typeof configuration.positionY === "number") {
      payload.positionY = configuration.positionY;
    }
    if (typeof configuration.anchorX === "number") {
      payload.anchorX = configuration.anchorX;
    }
    if (typeof configuration.anchorY === "number") {
      payload.anchorY = configuration.anchorY;
    }
    if (configuration.stageStyle) {
      payload.stageStyle = configuration.stageStyle;
    }

    this.post({
      type: "load-model",
      payload
    });
  }

  unloadModel(): void {
    this.post({
      type: "unload-model",
      payload: {}
    });
  }

  setFacing(facingRight: boolean): void {
    this.post({
      type: "set-facing",
      payload: { facingRight }
    });
  }

  setHidden(hidden: boolean): void {
    this.post({
      type: "set-hidden",
      payload: { hidden }
    });
  }

  playAction(action: PetLive2DHostAction | null): void {
    if (!action || (!action.expressionIndices.length && !action.motion)) {
      return;
    }

    this.post({
      type: "play-action",
      payload: {
        expressionIndices: action.expressionIndices,
        motion: action.motion ?? null
      }
    });
  }

  private post(message: HostMessage): void {
    if (!this.frameLoaded || !this.frame.contentWindow) {
      this.pendingMessages.push(message);
      return;
    }

    this.frame.contentWindow.postMessage(message, "*");
  }

  private flushPendingMessages(): void {
    if (!this.frame.contentWindow) {
      return;
    }

    for (const message of this.pendingMessages) {
      this.frame.contentWindow.postMessage(message, "*");
    }
    this.pendingMessages = [];
  }
}
