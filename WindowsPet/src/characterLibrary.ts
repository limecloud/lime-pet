import rawCatalog from "./assets/shared/character-library.json";

export type PetState =
  | "hidden"
  | "idle"
  | "walking"
  | "thinking"
  | "done";

export type PetRendererKind = "sprite" | "live2d";
export type PetLive2DTapKind = "single" | "double" | "triple";
export type PetLive2DLayoutMode = "contain" | "manual";

export interface PetLive2DMotion {
  group: string;
  index: number;
}

export interface PetLive2DStateAction {
  expression?: string;
  motion?: PetLive2DMotion;
}

export interface PetLive2DStageStyle {
  width?: number | null;
  height?: number | null;
}

export interface PetLive2DConfiguration {
  modelPath: string;
  modelPaths?: string[] | null;
  layoutMode?: PetLive2DLayoutMode;
  scale: number;
  offsetX: number;
  offsetY: number;
  positionX?: number | null;
  positionY?: number | null;
  anchorX?: number | null;
  anchorY?: number | null;
  stageStyle?: PetLive2DStageStyle | null;
  emotionMap: Record<string, number>;
  stateActions: Partial<Record<Exclude<PetState, "hidden">, PetLive2DStateAction>>;
  tapActions: Partial<Record<PetLive2DTapKind, PetLive2DMotion>>;
}

export interface PetCharacterTheme {
  id: string;
  displayName: string;
  switchBubble: string;
  renderer?: PetRendererKind;
  live2d?: PetLive2DConfiguration;
}

export interface PetCharacterCatalog {
  defaultCharacterId: string;
  characters: PetCharacterTheme[];
}

export interface PetLive2DHostAction {
  expressionIndices: number[];
  motion?: PetLive2DMotion;
}

export const characterCatalog = rawCatalog as PetCharacterCatalog;

export function characterRenderer(character: PetCharacterTheme): PetRendererKind {
  return character.renderer ?? "sprite";
}

export function characterById(characterId: string | null | undefined): PetCharacterTheme | null {
  if (!characterId) {
    return null;
  }

  return characterCatalog.characters.find((character) => character.id === characterId) ?? null;
}

export function defaultCharacter(): PetCharacterTheme {
  return (
    characterById(characterCatalog.defaultCharacterId) ??
    characterCatalog.characters[0] ?? {
      id: "fallback",
      displayName: "Lime Pet",
      switchBubble: "切换外观"
    }
  );
}

export function live2dStateAction(
  character: PetCharacterTheme,
  state: PetState,
): PetLive2DHostAction | null {
  if (state === "hidden" || characterRenderer(character) !== "live2d" || !character.live2d) {
    return null;
  }

  const action = character.live2d.stateActions[state];
  if (!action) {
    return null;
  }

  return {
    expressionIndices: resolveExpressionTags(character.live2d, action.expression ? [action.expression] : []),
    motion: action.motion
  };
}

export function live2dTapAction(
  character: PetCharacterTheme,
  tapKind: PetLive2DTapKind,
): PetLive2DHostAction | null {
  if (characterRenderer(character) !== "live2d" || !character.live2d) {
    return null;
  }

  const motion = character.live2d.tapActions[tapKind];
  if (!motion) {
    return null;
  }

  return {
    expressionIndices: [],
    motion
  };
}

export function live2dEnvelopeAction(
  character: PetCharacterTheme,
  payload?: Record<string, unknown>,
): PetLive2DHostAction | null {
  if (!payload || characterRenderer(character) !== "live2d" || !character.live2d) {
    return null;
  }

  const expressions = Array.isArray(payload.expressions) ? payload.expressions : [];
  const emotionTags = Array.isArray(payload.emotion_tags)
    ? payload.emotion_tags.filter((item): item is string => typeof item === "string")
    : [];

  const expressionIndices = [
    ...resolveExpressionValues(character.live2d, expressions),
    ...resolveExpressionTags(character.live2d, emotionTags)
  ].filter(uniqueNumber);

  const motion = typeof payload.motion_index === "number"
    ? {
        group: typeof payload.motion_group === "string" ? payload.motion_group : "",
        index: payload.motion_index
      }
    : undefined;

  if (!expressionIndices.length && !motion) {
    return null;
  }

  return {
    expressionIndices,
    motion
  };
}

export function live2dStageSize(configuration?: PetLive2DConfiguration | null): { width: number; height: number } {
  const width = typeof configuration?.stageStyle?.width === "number" ? configuration.stageStyle.width : 320;
  const height = typeof configuration?.stageStyle?.height === "number" ? configuration.stageStyle.height : 320;

  return {
    width,
    height
  };
}

function resolveExpressionValues(
  configuration: PetLive2DConfiguration,
  values: unknown[],
): number[] {
  return values.flatMap((value) => {
    if (typeof value === "number" && Number.isFinite(value)) {
      return [value];
    }
    if (typeof value === "string") {
      return resolveExpressionTags(configuration, [value]);
    }
    return [];
  });
}

function resolveExpressionTags(
  configuration: PetLive2DConfiguration,
  tags: string[],
): number[] {
  const normalizedMap = Object.fromEntries(
    Object.entries(configuration.emotionMap).map(([key, value]) => [key.toLowerCase(), value]),
  );

  return tags.flatMap((tag) => {
    const resolved = normalizedMap[tag.toLowerCase()];
    return typeof resolved === "number" ? [resolved] : [];
  });
}

function uniqueNumber(value: number, index: number, values: number[]): boolean {
  return values.indexOf(value) === index;
}
