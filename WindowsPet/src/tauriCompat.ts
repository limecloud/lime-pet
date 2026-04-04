import { invoke as tauriInvoke } from "@tauri-apps/api/core";
import {
  currentMonitor as tauriCurrentMonitor,
  getCurrentWindow,
  PhysicalPosition as TauriPhysicalPosition
} from "@tauri-apps/api/window";

interface TauriMetadataShape {
  currentWindow?: {
    label?: string;
  };
}

interface TauriInternalsShape {
  metadata?: TauriMetadataShape;
}

export interface WindowPositionLike {
  x: number;
  y: number;
}

export interface MonitorLike {
  position: WindowPositionLike;
  size: {
    width: number;
    height: number;
  };
}

interface WindowMoveEvent {
  payload: WindowPositionLike;
}

export interface AppWindowLike {
  setAlwaysOnTop(alwaysOnTop: boolean): Promise<void>;
  setPosition(position: WindowPositionLike | TauriPhysicalPosition): Promise<void>;
  onMoved(handler: (event: WindowMoveEvent) => void | Promise<void>): Promise<() => void>;
  startDragging(): Promise<void>;
  show(): Promise<void>;
  hide(): Promise<void>;
  close(): Promise<void>;
}

function tauriInternals(): TauriInternalsShape | undefined {
  if (typeof window === "undefined") {
    return undefined;
  }

  return (window as typeof window & { __TAURI_INTERNALS__?: TauriInternalsShape }).__TAURI_INTERNALS__;
}

export function isTauriRuntime(): boolean {
  return typeof tauriInternals()?.metadata?.currentWindow?.label === "string";
}

const previewWindow: AppWindowLike = {
  async setAlwaysOnTop() {},
  async setPosition() {},
  async onMoved() {
    return () => {};
  },
  async startDragging() {},
  async show() {},
  async hide() {},
  async close() {}
};

export const appWindow: AppWindowLike = (() => {
  if (!isTauriRuntime()) {
    return previewWindow;
  }

  const tauriWindow = getCurrentWindow();
  return {
    setAlwaysOnTop(alwaysOnTop) {
      return tauriWindow.setAlwaysOnTop(alwaysOnTop);
    },
    setPosition(position) {
      return tauriWindow.setPosition(position as TauriPhysicalPosition);
    },
    onMoved(handler) {
      return tauriWindow.onMoved(handler);
    },
    startDragging() {
      return tauriWindow.startDragging();
    },
    show() {
      return tauriWindow.show();
    },
    hide() {
      return tauriWindow.hide();
    },
    close() {
      return tauriWindow.close();
    }
  };
})();

export function toPhysicalPosition(x: number, y: number): WindowPositionLike | TauriPhysicalPosition {
  if (isTauriRuntime()) {
    return new TauriPhysicalPosition(x, y);
  }

  return { x, y };
}

export async function currentMonitorCompat(): Promise<MonitorLike | null> {
  if (isTauriRuntime()) {
    const monitor = await tauriCurrentMonitor();
    if (!monitor) {
      return null;
    }

    return {
      position: {
        x: monitor.position.x,
        y: monitor.position.y
      },
      size: {
        width: monitor.size.width,
        height: monitor.size.height
      }
    };
  }

  return {
    position: {
      x: typeof window !== "undefined" ? window.screenX : 0,
      y: typeof window !== "undefined" ? window.screenY : 0
    },
    size: {
      width: typeof window !== "undefined" ? window.screen.availWidth || window.innerWidth : 1440,
      height: typeof window !== "undefined" ? window.screen.availHeight || window.innerHeight : 900
    }
  };
}

export async function invokeCompat<TResponse>(
  command: string,
  args?: Record<string, unknown>,
): Promise<TResponse> {
  if (isTauriRuntime()) {
    return tauriInvoke<TResponse>(command, args);
  }

  if (command === "load_launch_config") {
    return {
      endpoint: null,
      client_id: "lime-pet-browser-preview",
      protocol_version: 1
    } as TResponse;
  }

  throw new Error(`浏览器预览不支持调用 Tauri 指令: ${command}`);
}
