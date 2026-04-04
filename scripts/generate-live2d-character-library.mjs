import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const currentDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(currentDir, "..");
const modelsRoot = path.join(repoRoot, "LimePet", "Resources", "live2d-models", "oml2d");
const libraryTargets = [
  path.join(repoRoot, "LimePet", "Resources", "character-library.json"),
  path.join(repoRoot, "WindowsPet", "src", "assets", "shared", "character-library.json")
];
const presetsPath = path.join(repoRoot, "LimePet", "Resources", "live2d-model-presets.json");

const spriteCharacter = {
  id: "dewy-lime",
  displayName: "雾隐青柠",
  switchBubble: "切换到青橙守望形态"
};

const selectedModels = JSON.parse(fs.readFileSync(presetsPath, "utf8"));

const motionCandidateMap = {
  idle: ["Idle", "idle", "rest", "sleepy", "null", "", "talk"],
  walking: ["walk", "Walk", "run", "Run", "move", "Move", "Idle", "idle", "rest"],
  thinking: ["think", "Thinking", "thinking", "talk", "Talk", "flick_head", "shake", "idle", "Idle"],
  done: ["done", "Done", "happy", "Happy", "success", "Success", "talk", "Talk", "idle", "Idle"],
  single: ["tap_body", "Tap", "tap", "flick_head", "talk", "null", ""],
  double: ["flick_head", "Taphead", "talk", "tap_body", "Tap", "tap", "null", ""],
  triple: ["talk", "tap_body", "shake", "Tap", "tap", "flick_head", "null", ""]
};

function readModelConfig(spec) {
  const modelPath = resolveModelConfigPath(spec, resolveEntryList(spec)[0]);
  const raw = fs.readFileSync(modelPath, "utf8");
  return JSON.parse(raw);
}

function resolveEntryList(spec) {
  if (Array.isArray(spec.paths) && spec.paths.length > 0) {
    return spec.paths.filter((value) => typeof value === "string" && value.length > 0);
  }

  if (typeof spec.entry === "string" && spec.entry.length > 0) {
    return [spec.entry];
  }

  throw new Error(`Model preset ${spec.id} is missing an entry or paths array`);
}

function resolveModelConfigPath(spec, entry) {
  if (entry.includes("/")) {
    return path.join(modelsRoot, entry);
  }

  return path.join(modelsRoot, spec.dir, entry);
}

function resolveLogicalModelPath(spec, entry) {
  if (entry.includes("/")) {
    return path.posix.join("live2d-models", "oml2d", entry);
  }

  return path.posix.join("live2d-models", "oml2d", spec.dir, entry);
}

function motionGroupsFromConfig(config) {
  if (config?.FileReferences?.Motions && typeof config.FileReferences.Motions === "object") {
    return config.FileReferences.Motions;
  }

  if (config?.motions && typeof config.motions === "object") {
    return config.motions;
  }

  return {};
}

function findGroupName(motionGroups, candidates) {
  const names = Object.keys(motionGroups);
  for (const candidate of candidates) {
    if (names.includes(candidate)) {
      return candidate;
    }
  }

  return null;
}

function clampMotionIndex(motionGroups, groupName, preferredIndex) {
  if (!groupName) {
    return null;
  }

  const entries = motionGroups[groupName];
  if (!Array.isArray(entries) || entries.length === 0) {
    return null;
  }

  return Math.min(preferredIndex, entries.length - 1);
}

function makeMotion(motionGroups, candidates, preferredIndex) {
  const groupName = findGroupName(motionGroups, candidates);
  const index = clampMotionIndex(motionGroups, groupName, preferredIndex);

  if (groupName === null || index === null) {
    return null;
  }

  return {
    group: groupName,
    index
  };
}

function expressionCountFromConfig(config) {
  if (Array.isArray(config?.expressions)) {
    return config.expressions.length;
  }

  return 0;
}

function defaultEmotionMap(spec, config) {
  if (spec.emotionMap) {
    return spec.emotionMap;
  }

  if (expressionCountFromConfig(config) >= 4) {
    return {
      neutral: 0,
      joy: 1,
      surprise: 2,
      sadness: 3
    };
  }

  return {};
}

function resolveScale(spec, config) {
  if (typeof spec.scale === "number" && Number.isFinite(spec.scale)) {
    return spec.scale;
  }

  const layoutWidth = config?.layout?.width;
  if (typeof layoutWidth === "number" && Number.isFinite(layoutWidth) && layoutWidth > 0) {
    const derivedScale = 1.9 / layoutWidth;
    return Number(Math.min(1.08, Math.max(0.72, derivedScale)).toFixed(2));
  }

  return 0.94;
}

function resolveOffsetY(spec, config) {
  if (typeof spec.offsetY === "number" && Number.isFinite(spec.offsetY)) {
    return spec.offsetY;
  }

  const layoutCenterY = config?.layout?.center_y;
  if (typeof layoutCenterY === "number" && Number.isFinite(layoutCenterY)) {
    return Number((layoutCenterY * 18).toFixed(0));
  }

  return 0;
}

function resolveLayoutMode(spec) {
  return spec.layoutMode === "manual" ? "manual" : "contain";
}

function resolvePosition(spec) {
  if (Array.isArray(spec.position) && spec.position.length >= 2) {
    const [x, y] = spec.position;
    if (typeof x === "number" && Number.isFinite(x) && typeof y === "number" && Number.isFinite(y)) {
      return { x, y };
    }
  }

  return null;
}

function resolveAnchor(spec) {
  if (Array.isArray(spec.anchor) && spec.anchor.length >= 2) {
    const [x, y] = spec.anchor;
    if (typeof x === "number" && Number.isFinite(x) && typeof y === "number" && Number.isFinite(y)) {
      return { x, y };
    }
  }

  return null;
}

function resolveStageStyle(spec) {
  if (!spec.stageStyle || typeof spec.stageStyle !== "object") {
    return null;
  }

  const width = typeof spec.stageStyle.width === "number" && Number.isFinite(spec.stageStyle.width)
    ? spec.stageStyle.width
    : null;
  const height = typeof spec.stageStyle.height === "number" && Number.isFinite(spec.stageStyle.height)
    ? spec.stageStyle.height
    : null;

  if (width === null && height === null) {
    return null;
  }

  return { width, height };
}

function createCharacterEntry(spec) {
  const config = readModelConfig(spec);
  const motionGroups = motionGroupsFromConfig(config);
  const modelPaths = resolveEntryList(spec).map((entry) => resolveLogicalModelPath(spec, entry));
  const position = resolvePosition(spec);
  const anchor = resolveAnchor(spec);
  const stageStyle = resolveStageStyle(spec);

  return {
    id: spec.id,
    displayName: spec.displayName,
    switchBubble: `切换到 ${spec.displayName} 模型`,
    renderer: "live2d",
    live2d: {
      modelPath: modelPaths[0],
      modelPaths: modelPaths.length > 1 ? modelPaths : null,
      layoutMode: resolveLayoutMode(spec),
      scale: resolveScale(spec, config),
      offsetX: spec.offsetX ?? 0,
      offsetY: resolveOffsetY(spec, config),
      positionX: position?.x ?? null,
      positionY: position?.y ?? null,
      anchorX: anchor?.x ?? null,
      anchorY: anchor?.y ?? null,
      stageStyle,
      emotionMap: defaultEmotionMap(spec, config),
      stateActions: {
        idle: makeMotion(motionGroups, motionCandidateMap.idle, 0)
          ? { motion: makeMotion(motionGroups, motionCandidateMap.idle, 0) }
          : null,
        walking: makeMotion(motionGroups, motionCandidateMap.walking, 1)
          ? { motion: makeMotion(motionGroups, motionCandidateMap.walking, 1) }
          : null,
        thinking: makeMotion(motionGroups, motionCandidateMap.thinking, 2)
          ? { motion: makeMotion(motionGroups, motionCandidateMap.thinking, 2) }
          : null,
        done: makeMotion(motionGroups, motionCandidateMap.done, 3)
          ? { motion: makeMotion(motionGroups, motionCandidateMap.done, 3) }
          : null
      },
      tapActions: {
        single: makeMotion(motionGroups, motionCandidateMap.single, 0),
        double: makeMotion(motionGroups, motionCandidateMap.double, 1),
        triple: makeMotion(motionGroups, motionCandidateMap.triple, 2)
      }
    }
  };
}

const library = {
  defaultCharacterId: "dewy-lime",
  characters: [
    spriteCharacter,
    ...selectedModels.map(createCharacterEntry)
  ]
};

for (const target of libraryTargets) {
  fs.writeFileSync(target, `${JSON.stringify(library, null, 2)}\n`);
}
console.log(`Generated character library with ${selectedModels.length} Live2D models`);
