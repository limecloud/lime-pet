import crypto from "node:crypto";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const currentDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(currentDir, "..");
const workspaceRoot = path.resolve(repoRoot, "..");
const defaultModelsRoot = path.join(repoRoot, "LimePet", "Resources", "live2d-models", "oml2d");
const defaultPresetsPath = path.join(repoRoot, "LimePet", "Resources", "live2d-model-presets.json");
const defaultBundledCharacterLibraryTargets = [
  path.join(repoRoot, "LimePet", "Resources", "character-library.json"),
  path.join(repoRoot, "WindowsPet", "src", "assets", "shared", "character-library.json")
];
const defaultLive2dCatalogTargets = [
  path.join(repoRoot, "LimePet", "Resources", "live2d-model-catalog.json"),
  path.join(
    workspaceRoot,
    "limecore",
    "apps",
    "website",
    "data",
    "pet-model-catalog.seed.json"
  ),
  path.join(
    workspaceRoot,
    "limecore",
    "services",
    "control-plane-svc",
    "internal",
    "service",
    "embedded",
    "pet_model_catalog.seed.json"
  )
];

const catalogVersion = 1;
let activeModelsRoot = defaultModelsRoot;
let activeAssetBaseURL = "";
const generatedManifestRoot = path.join(
  repoRoot,
  "LimePet",
  "Resources",
  "live2d-models",
  "oml2d",
  "_generated"
);
const generatedManifestEntries = new Map();
const assetEntryCache = new Map();
const collectedAssetsCache = new Map();
const previewComposerCandidates = [
  "magick",
  "/opt/homebrew/bin/magick"
];
let resolvedPreviewComposer = undefined;

const spriteCharacter = {
  id: "dewy-lime",
  displayName: "雾隐青柠",
  switchBubble: "切换到青柠守望形态"
};

function firstNonEmpty(...values) {
  for (const value of values) {
    if (typeof value === "string" && value.trim()) {
      return value.trim();
    }
  }

  return "";
}

function parseBool(value, defaultValue = false) {
  if (typeof value !== "string") {
    return defaultValue;
  }

  switch (value.trim().toLowerCase()) {
    case "1":
    case "true":
    case "yes":
    case "on":
      return true;
    case "0":
    case "false":
    case "no":
    case "off":
      return false;
    default:
      return defaultValue;
  }
}

function normalizeTargets(values, fallback) {
  const flattened = [];

  for (const value of values) {
    if (Array.isArray(value)) {
      flattened.push(...value);
      continue;
    }

    if (typeof value === "string" && value.includes(path.delimiter)) {
      flattened.push(...value.split(path.delimiter));
      continue;
    }

    flattened.push(value);
  }

  const normalized = flattened
    .map((value) => String(value ?? "").trim())
    .filter(Boolean);

  return normalized.length > 0 ? Array.from(new Set(normalized)) : [...fallback];
}

function parseArgs(argv) {
  const options = {
    modelsRoot: firstNonEmpty(process.env.LIVE2D_MODELS_ROOT, defaultModelsRoot),
    presetsPath: firstNonEmpty(process.env.LIVE2D_PRESETS_PATH, defaultPresetsPath),
    assetBaseURL: firstNonEmpty(process.env.LIVE2D_ASSET_BASE_URL),
    catalogTargets: normalizeTargets(
      [process.env.LIVE2D_CATALOG_TARGETS],
      defaultLive2dCatalogTargets
    ),
    characterLibraryTargets: normalizeTargets(
      [process.env.LIVE2D_CHARACTER_LIBRARY_TARGETS],
      defaultBundledCharacterLibraryTargets
    ),
    skipCatalog: parseBool(process.env.LIVE2D_SKIP_CATALOG, false),
    skipCharacterLibrary: parseBool(process.env.LIVE2D_SKIP_CHARACTER_LIBRARY, false),
    dryRun: false
  };

  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    switch (token) {
      case "--models-root":
        options.modelsRoot = argv[index + 1] ?? "";
        index += 1;
        break;
      case "--presets":
      case "--presets-path":
        options.presetsPath = argv[index + 1] ?? "";
        index += 1;
        break;
      case "--asset-base-url":
        options.assetBaseURL = argv[index + 1] ?? "";
        index += 1;
        break;
      case "--catalog-target":
        options.catalogTargets.push(argv[index + 1] ?? "");
        index += 1;
        break;
      case "--character-library-target":
        options.characterLibraryTargets.push(argv[index + 1] ?? "");
        index += 1;
        break;
      case "--skip-catalog":
        options.skipCatalog = true;
        break;
      case "--skip-character-library":
        options.skipCharacterLibrary = true;
        break;
      case "--dry-run":
        options.dryRun = true;
        break;
      default:
        throw new Error(`未知参数: ${token}`);
    }
  }

  options.catalogTargets = normalizeTargets(options.catalogTargets, defaultLive2dCatalogTargets);
  options.characterLibraryTargets = normalizeTargets(
    options.characterLibraryTargets,
    defaultBundledCharacterLibraryTargets
  );

  return options;
}

function assertReadableFile(filePath, label) {
  const resolvedPath = path.resolve(String(filePath ?? "").trim());
  if (!resolvedPath) {
    throw new Error(`${label} 不能为空`);
  }

  if (!fs.existsSync(resolvedPath)) {
    throw new Error(`${label} 不存在: ${resolvedPath}`);
  }

  if (!fs.statSync(resolvedPath).isFile()) {
    throw new Error(`${label} 不是文件: ${resolvedPath}`);
  }

  return resolvedPath;
}

function assertReadableDirectory(directoryPath, label) {
  const resolvedPath = path.resolve(String(directoryPath ?? "").trim());
  if (!resolvedPath) {
    throw new Error(`${label} 不能为空`);
  }

  if (!fs.existsSync(resolvedPath)) {
    throw new Error(`${label} 不存在: ${resolvedPath}`);
  }

  if (!fs.statSync(resolvedPath).isDirectory()) {
    throw new Error(`${label} 不是目录: ${resolvedPath}`);
  }

  return resolvedPath;
}

const motionCandidateMap = {
  idle: ["Idle", "idle", "rest", "sleepy", "null", "", "talk"],
  walking: ["walk", "Walk", "run", "Run", "move", "Move", "Idle", "idle", "rest"],
  thinking: ["think", "Thinking", "thinking", "talk", "Talk", "flick_head", "shake", "idle", "Idle"],
  done: ["done", "Done", "happy", "Happy", "success", "Success", "talk", "Talk", "idle", "Idle"],
  single: ["tap_body", "Tap", "tap", "flick_head", "talk", "null", ""],
  double: ["flick_head", "Taphead", "talk", "tap_body", "Tap", "tap", "null", ""],
  triple: ["talk", "tap_body", "shake", "Tap", "tap", "flick_head", "null", ""]
};

const excludedExtensions = new Set([".gif", ".jpg", ".jpeg", ".md", ".txt"]);
const excludedSuffixes = [".pil.png"];
const previewImageExtensions = new Set([".png", ".jpg", ".jpeg", ".webp", ".gif"]);
const previewKeywords = ["preview", "cover", "thumb", "thumbnail", "poster", "sample", "demo"];

function readJSON(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function normalizePresetDocument(rawValue) {
  if (Array.isArray(rawValue)) {
    return {
      excludeDirs: [],
      directories: rawValue
    };
  }

  if (!rawValue || typeof rawValue !== "object") {
    throw new Error("模型预设文件必须是数组或对象");
  }

  const directoryArray = Array.isArray(rawValue.directories)
    ? rawValue.directories
    : Array.isArray(rawValue.items)
      ? rawValue.items
      : [];
  const excludeDirs = Array.isArray(rawValue.excludeDirs)
    ? rawValue.excludeDirs
    : Array.isArray(rawValue.excludedDirs)
      ? rawValue.excludedDirs
      : [];

  return {
    excludeDirs,
    directories: directoryArray
  };
}

function normalizeDirectoryName(value) {
  return String(value ?? "").trim();
}

function slugifyIdentifier(source) {
  const slug = String(source ?? "")
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");

  return slug || "live2d-model";
}

function titleCaseLabel(source) {
  return humanizeLabel(source)
    .split(" ")
    .filter(Boolean)
    .map((token) => {
      if (/^[A-Z0-9]+$/.test(token)) {
        return token;
      }

      if (/\d/.test(token)) {
        return token.toUpperCase();
      }

      return token.charAt(0).toUpperCase() + token.slice(1);
    })
    .join(" ");
}

function isModelEntryFile(fileName) {
  return /(\.model3\.json|\.model\.json|model\.json|index\.json)$/i.test(fileName);
}

function normalizeModelReferencePath(value) {
  const normalizedValue = String(value ?? "").trim().replace(/\\/g, "/");
  if (!normalizedValue) {
    return "";
  }

  if (/^(https?:|file:|data:)/i.test(normalizedValue)) {
    return normalizedValue;
  }

  return normalizedValue.replace(/^\/+/, "");
}

function uniqueNormalizedPaths(values) {
  const seen = new Set();
  const result = [];

  for (const value of values) {
    const normalizedValue = normalizeModelReferencePath(value);
    if (!normalizedValue || seen.has(normalizedValue)) {
      continue;
    }

    seen.add(normalizedValue);
    result.push(normalizedValue);
  }

  return result;
}

function resolveConfigTextures(config) {
  if (Array.isArray(config?.textures)) {
    return config.textures;
  }

  if (Array.isArray(config?.FileReferences?.Textures)) {
    return config.FileReferences.Textures;
  }

  return [];
}

function resolveTextureSelection(originalTextures, selectedTexturePaths) {
  const normalizedOriginalTextures = uniqueNormalizedPaths(originalTextures);
  if (Array.isArray(selectedTexturePaths)) {
    const normalizedSelection = selectedTexturePaths.map(normalizeModelReferencePath).filter(Boolean);
    if (normalizedSelection.length > 0) {
      return normalizedSelection;
    }
  }

  const normalizedTexturePath = normalizeModelReferencePath(selectedTexturePaths);
  if (!normalizedTexturePath) {
    return normalizedOriginalTextures;
  }

  const slotCount = Math.max(normalizedOriginalTextures.length, 1);
  return Array.from({ length: slotCount }, () => normalizedTexturePath);
}

function isTextureDirectoryPath(filePath) {
  return /(^|\/)(textures?(?:\.[^/]+)?|texture_\d+)(\/|$)/i.test(
    String(filePath ?? "").replace(/\\/g, "/")
  );
}

function rewriteModelReferencePath(value, sourceEntryDirectory, generatedEntryDirectory) {
  const normalizedValue = normalizeModelReferencePath(value);
  if (!normalizedValue || /^(https?:|file:|data:)/i.test(normalizedValue)) {
    return normalizedValue;
  }

  return path.posix.relative(
    generatedEntryDirectory,
    path.posix.join(sourceEntryDirectory, normalizedValue)
  );
}

function rewriteMotionCollection(motions, fileKey, soundKeys, sourceEntryDirectory, generatedEntryDirectory) {
  if (!motions || typeof motions !== "object") {
    return motions;
  }

  const rewritten = {};
  for (const [groupName, entries] of Object.entries(motions)) {
    rewritten[groupName] = Array.isArray(entries)
      ? entries.map((entry) => {
        if (!entry || typeof entry !== "object") {
          return entry;
        }

        const nextEntry = { ...entry };
        if (typeof nextEntry[fileKey] === "string") {
          nextEntry[fileKey] = rewriteModelReferencePath(
            nextEntry[fileKey],
            sourceEntryDirectory,
            generatedEntryDirectory
          );
        }

        for (const soundKey of soundKeys) {
          if (typeof nextEntry[soundKey] === "string") {
            nextEntry[soundKey] = rewriteModelReferencePath(
              nextEntry[soundKey],
              sourceEntryDirectory,
              generatedEntryDirectory
            );
          }
        }

        return nextEntry;
      })
      : entries;
  }

  return rewritten;
}

function buildGeneratedTextureWardrobeConfig(config, sourceEntry, selectedTexturePaths) {
  const sourceEntryDirectory = path.posix.dirname(sourceEntry);
  const clonedConfig = JSON.parse(JSON.stringify(config));
  const generatedEntryDirectory = path.posix.join("_generated", sourceEntryDirectory);
  const originalTextures = resolveConfigTextures(config);
  const resolvedTexturePaths = resolveTextureSelection(originalTextures, selectedTexturePaths).map(
    (texturePath) => rewriteModelReferencePath(
      texturePath,
      sourceEntryDirectory,
      generatedEntryDirectory
    )
  );

  if (Array.isArray(clonedConfig.textures)) {
    clonedConfig.textures = resolvedTexturePaths;
  }

  if (clonedConfig.model) {
    clonedConfig.model = rewriteModelReferencePath(
      clonedConfig.model,
      sourceEntryDirectory,
      generatedEntryDirectory
    );
  }
  if (clonedConfig.physics) {
    clonedConfig.physics = rewriteModelReferencePath(
      clonedConfig.physics,
      sourceEntryDirectory,
      generatedEntryDirectory
    );
  }
  if (clonedConfig.pose) {
    clonedConfig.pose = rewriteModelReferencePath(
      clonedConfig.pose,
      sourceEntryDirectory,
      generatedEntryDirectory
    );
  }
  if (Array.isArray(clonedConfig.expressions)) {
    clonedConfig.expressions = clonedConfig.expressions.map((expression) => {
      if (!expression || typeof expression !== "object" || typeof expression.file !== "string") {
        return expression;
      }

      return {
        ...expression,
        file: rewriteModelReferencePath(
          expression.file,
          sourceEntryDirectory,
          generatedEntryDirectory
        )
      };
    });
  }
  if (clonedConfig.motions) {
    clonedConfig.motions = rewriteMotionCollection(
      clonedConfig.motions,
      "file",
      ["sound"],
      sourceEntryDirectory,
      generatedEntryDirectory
    );
  }

  if (clonedConfig.FileReferences && typeof clonedConfig.FileReferences === "object") {
    const fileReferences = { ...clonedConfig.FileReferences };

    if (Array.isArray(fileReferences.Textures)) {
      fileReferences.Textures = resolvedTexturePaths;
    }

    for (const key of ["Moc", "Physics", "Pose", "DisplayInfo", "UserData"]) {
      if (typeof fileReferences[key] === "string") {
        fileReferences[key] = rewriteModelReferencePath(
          fileReferences[key],
          sourceEntryDirectory,
          generatedEntryDirectory
        );
      }
    }

    if (Array.isArray(fileReferences.Expressions)) {
      fileReferences.Expressions = fileReferences.Expressions.map((expression) => {
        if (!expression || typeof expression !== "object" || typeof expression.File !== "string") {
          return expression;
        }

        return {
          ...expression,
          File: rewriteModelReferencePath(
            expression.File,
            sourceEntryDirectory,
            generatedEntryDirectory
          )
        };
      });
    }

    if (fileReferences.Motions) {
      fileReferences.Motions = rewriteMotionCollection(
        fileReferences.Motions,
        "File",
        ["Sound", "sound"],
        sourceEntryDirectory,
        generatedEntryDirectory
      );
    }

    clonedConfig.FileReferences = fileReferences;
  }

  return clonedConfig;
}

function readTextureCombinationCache(sourceEntry) {
  const sourceEntryDirectory = path.posix.dirname(sourceEntry);
  const cachePath = path.join(
    activeModelsRoot,
    ...sourceEntryDirectory.split("/"),
    "textures.cache"
  );

  if (!fs.existsSync(cachePath) || !fs.statSync(cachePath).isFile()) {
    return [];
  }

  const rawValue = readJSON(cachePath);
  if (!Array.isArray(rawValue)) {
    return [];
  }

  return rawValue
    .filter((entry) => Array.isArray(entry) && entry.length > 0)
    .map((entry) => entry.map(normalizeModelReferencePath).filter(Boolean))
    .filter((entry) => entry.length > 0);
}

function textureRoleLabel(role) {
  switch (role) {
    case "hat":
      return "Hat";
    case "headwear":
      return "Headwear";
    default:
      return titleCaseLabel(role);
  }
}

function parseTextureVariantDescriptor(texturePath) {
  const normalizedPath = normalizeModelReferencePath(texturePath);
  const baseName = path.posix.basename(
    normalizedPath,
    path.posix.extname(normalizedPath)
  );
  const matched = baseName.match(/^(.*?)-(upper|lower|hat|headwear)$/i);
  if (matched) {
    return {
      theme: matched[1],
      role: matched[2].toLowerCase()
    };
  }

  return {
    theme: baseName,
    role: "texture"
  };
}

function buildTextureCombinationLabel(texturePaths, variableIndices) {
  const descriptors = variableIndices.map((index) => parseTextureVariantDescriptor(texturePaths[index]));
  const outfitThemes = Array.from(
    new Set(
      descriptors
        .filter((descriptor) => descriptor.role === "upper" || descriptor.role === "lower")
        .map((descriptor) => descriptor.theme)
        .filter(Boolean)
    )
  );
  const accessoryLabels = descriptors
    .filter((descriptor) => descriptor.role !== "upper" && descriptor.role !== "lower")
    .map((descriptor) => {
      const themeLabel = titleCaseLabel(descriptor.theme);
      if (descriptor.role === "texture") {
        return themeLabel;
      }

      return `${themeLabel} ${textureRoleLabel(descriptor.role)}`;
    });

  const parts = [];
  if (outfitThemes.length > 0) {
    parts.push(outfitThemes.map((theme) => titleCaseLabel(theme)).join(" + "));
  }
  parts.push(...accessoryLabels);

  if (parts.length > 0) {
    return parts.join(" + ");
  }

  const fallbackLabel = texturePaths
    .map((texturePath) => titleCaseLabel(path.posix.basename(texturePath, path.posix.extname(texturePath))))
    .filter(Boolean)
    .join(" + ");
  return fallbackLabel || "Wardrobe";
}

function resolvePreviewComposer() {
  if (resolvedPreviewComposer !== undefined) {
    return resolvedPreviewComposer;
  }

  for (const candidate of previewComposerCandidates) {
    const result = spawnSync(candidate, ["-version"], { encoding: "utf8" });
    if (result.status === 0) {
      resolvedPreviewComposer = candidate;
      return resolvedPreviewComposer;
    }
  }

  resolvedPreviewComposer = null;
  return resolvedPreviewComposer;
}

function createGeneratedPreviewOutput(sourceEntryDirectory, generatedFileName) {
  const previewFileName = generatedFileName.replace(/\.json$/i, ".png");
  return {
    previewEntry: path.posix.join("_generated", sourceEntryDirectory, "previews", previewFileName),
    previewFilePath: path.join(
      generatedManifestRoot,
      ...sourceEntryDirectory.split("/"),
      "previews",
      previewFileName
    )
  };
}

function generateTextureCombinationPreview(sourceEntry, generatedFileName, texturePaths) {
  const previewComposer = resolvePreviewComposer();
  if (!previewComposer) {
    return null;
  }

  const sourceEntryDirectory = path.posix.dirname(sourceEntry);
  const sourceTextureFiles = texturePaths.map((texturePath) => path.join(
    activeModelsRoot,
    ...sourceEntryDirectory.split("/"),
    ...normalizeModelReferencePath(texturePath).split("/")
  ));

  if (
    sourceTextureFiles.length === 0 ||
    sourceTextureFiles.some((filePath) => !fs.existsSync(filePath) || !fs.statSync(filePath).isFile())
  ) {
    return null;
  }

  const { previewEntry, previewFilePath } = createGeneratedPreviewOutput(
    sourceEntryDirectory,
    generatedFileName
  );
  if (fs.existsSync(previewFilePath) && fs.statSync(previewFilePath).isFile()) {
    return previewEntry;
  }
  fs.mkdirSync(path.dirname(previewFilePath), { recursive: true });

  const result = spawnSync(
    previewComposer,
    [
      ...sourceTextureFiles,
      "-background",
      "none",
      "-layers",
      "flatten",
      "-trim",
      "+repage",
      "-resize",
      "768x768",
      "-gravity",
      "center",
      "-background",
      "none",
      "-extent",
      "768x768",
      previewFilePath
    ],
    { encoding: "utf8" }
  );

  if (result.status !== 0) {
    console.warn(
      `生成组合预览图失败: ${generatedFileName}\n${String(result.stderr ?? result.stdout ?? "").trim()}`
    );
    return null;
  }

  return previewEntry;
}

function registerGeneratedTextureCombinationWardrobes(spec) {
  if (spec.expandTextureCacheToWardrobes !== true) {
    return spec;
  }

  const originalEntries = resolveEntryList(spec);
  const sourceEntry = normalizeDirectoryName(spec.textureWardrobeEntry) || originalEntries[0];
  if (!sourceEntry || !originalEntries.includes(sourceEntry)) {
    return spec;
  }

  const sourceConfig = readJSON(resolveModelConfigPath(spec, sourceEntry));
  const baseTextures = uniqueNormalizedPaths(resolveConfigTextures(sourceConfig));
  const combinationCache = readTextureCombinationCache(sourceEntry)
    .filter((entry) => entry.length === baseTextures.length);

  if (combinationCache.length <= 1) {
    return spec;
  }

  const variableIndices = baseTextures.reduce((result, _, index) => {
    const uniqueValues = new Set(combinationCache.map((entry) => entry[index]));
    if (uniqueValues.size > 1) {
      result.push(index);
    }
    return result;
  }, []);
  if (variableIndices.length === 0) {
    return spec;
  }

  const sourceEntryDirectory = path.posix.dirname(sourceEntry);
  const sourceBaseName = path.posix.basename(sourceEntry, path.posix.extname(sourceEntry));
  const generatedDirectoryPath = path.join(generatedManifestRoot, ...sourceEntryDirectory.split("/"));
  fs.mkdirSync(generatedDirectoryPath, { recursive: true });

  const rewrittenEntries = [];
  const rewrittenLabels = [];

  for (const [index, combination] of combinationCache.entries()) {
    const label = buildTextureCombinationLabel(combination, variableIndices);
    const generatedFileName = `${sourceBaseName}.combo-${String(index + 1).padStart(3, "0")}.${slugifyIdentifier(label)}.json`;
    const generatedEntry = path.posix.join("_generated", sourceEntryDirectory, generatedFileName);
    const generatedFilePath = path.join(generatedDirectoryPath, generatedFileName);
    const generatedConfig = buildGeneratedTextureWardrobeConfig(
      sourceConfig,
      sourceEntry,
      combination
    );
    const generatedPreviewPath = generateTextureCombinationPreview(
      sourceEntry,
      generatedFileName,
      combination
    );

    fs.writeFileSync(generatedFilePath, `${JSON.stringify(generatedConfig, null, 2)}\n`);
    generatedManifestEntries.set(generatedEntry, {
      filePath: generatedFilePath,
      sourceEntry,
      previewPath: generatedPreviewPath,
      label
    });

    rewrittenEntries.push(generatedEntry);
    rewrittenLabels.push(label);
  }

  return {
    ...spec,
    paths: rewrittenEntries,
    wardrobeLabels: rewrittenLabels
  };
}

function registerGeneratedTextureWardrobes(spec) {
  if (spec.expandTexturesToWardrobes !== true) {
    return spec;
  }

  const originalEntries = resolveEntryList(spec);
  const sourceEntries = Array.isArray(spec.textureWardrobeEntries) && spec.textureWardrobeEntries.length > 0
    ? uniqueNormalizedPaths(spec.textureWardrobeEntries)
    : uniqueNormalizedPaths([spec.textureWardrobeEntry || originalEntries[0]]);
  const originalLabels = Array.isArray(spec.wardrobeLabels) ? spec.wardrobeLabels : [];
  const expandedEntriesBySource = new Map();
  const expandedLabelsBySource = new Map();

  for (const sourceEntry of sourceEntries) {
    if (!originalEntries.includes(sourceEntry)) {
      continue;
    }

    const sourceConfig = readJSON(resolveModelConfigPath(spec, sourceEntry));
    const sourceTextures = resolveWardrobeTextureCandidates(spec, sourceEntry, sourceConfig);
    if (sourceTextures.length <= 1) {
      continue;
    }

    const sourceEntryDirectory = path.posix.dirname(sourceEntry);
    const sourceBaseName = path.posix.basename(sourceEntry, path.posix.extname(sourceEntry));
    const sourceLabel = titleCaseLabel(path.posix.basename(sourceEntryDirectory));
    const expandedEntries = [];
    const expandedLabels = [];

    fs.mkdirSync(path.join(generatedManifestRoot, ...sourceEntryDirectory.split("/")), { recursive: true });

    for (const [index, texturePath] of sourceTextures.entries()) {
      const textureBaseName = path.posix.basename(
        texturePath,
        path.posix.extname(texturePath)
      );
      const generatedFileName = `${sourceBaseName}.wardrobe-${String(index + 1).padStart(3, "0")}.${slugifyIdentifier(textureBaseName)}.json`;
      const generatedEntry = path.posix.join("_generated", sourceEntryDirectory, generatedFileName);
      const generatedFilePath = path.join(
        generatedManifestRoot,
        ...sourceEntryDirectory.split("/"),
        generatedFileName
      );
    const generatedConfig = buildGeneratedTextureWardrobeConfig(
      sourceConfig,
      sourceEntry,
      texturePath
    );

      fs.writeFileSync(generatedFilePath, `${JSON.stringify(generatedConfig, null, 2)}\n`);
      generatedManifestEntries.set(generatedEntry, {
        filePath: generatedFilePath,
        sourceEntry,
        previewPath: path.posix.join(sourceEntryDirectory, texturePath),
        label: titleCaseLabel(textureBaseName),
        sourceLabel
      });

      expandedEntries.push(generatedEntry);
      expandedLabels.push(titleCaseLabel(textureBaseName));
    }

    expandedEntriesBySource.set(sourceEntry, expandedEntries);
    expandedLabelsBySource.set(sourceEntry, expandedLabels);
  }

  if (expandedEntriesBySource.size === 0) {
    return spec;
  }

  const rewrittenEntries = [];
  const rewrittenLabels = [];
  for (const [index, entry] of originalEntries.entries()) {
    if (expandedEntriesBySource.has(entry)) {
      rewrittenEntries.push(...expandedEntriesBySource.get(entry));
      rewrittenLabels.push(...expandedLabelsBySource.get(entry));
      continue;
    }

    rewrittenEntries.push(entry);

    if (typeof originalLabels[index] === "string" && originalLabels[index].trim()) {
      rewrittenLabels.push(originalLabels[index].trim());
    } else {
      rewrittenLabels.push(resolveWardrobeLabel(spec, entry, index));
    }
  }

  const duplicateLabelCounts = rewrittenLabels.reduce((result, label) => {
    const normalizedLabel = String(label ?? "").trim().toLowerCase();
    if (!normalizedLabel) {
      return result;
    }

    result.set(normalizedLabel, (result.get(normalizedLabel) ?? 0) + 1);
    return result;
  }, new Map());

  const disambiguatedLabels = rewrittenEntries.map((entry, index) => {
    const label = rewrittenLabels[index];
    const normalizedLabel = String(label ?? "").trim().toLowerCase();
    const generatedManifest = generatedManifestEntries.get(entry);
    if ((duplicateLabelCounts.get(normalizedLabel) ?? 0) <= 1 || !generatedManifest?.sourceLabel) {
      return label;
    }

    return `${label} (${generatedManifest.sourceLabel})`;
  });

  for (const [index, entry] of rewrittenEntries.entries()) {
    const generatedManifest = generatedManifestEntries.get(entry);
    if (generatedManifest) {
      generatedManifest.label = disambiguatedLabels[index];
    }
  }

  return {
    ...spec,
    paths: rewrittenEntries,
    wardrobeLabels: disambiguatedLabels
  };
}

function isWardrobeTextureCandidate(relativePath) {
  const normalizedPath = normalizeModelReferencePath(relativePath).toLowerCase();
  if (!normalizedPath) {
    return false;
  }

  if (excludedSuffixes.some((suffix) => normalizedPath.endsWith(suffix))) {
    return false;
  }

  if (!previewImageExtensions.has(path.posix.extname(normalizedPath))) {
    return false;
  }

  const baseName = path.posix.basename(normalizedPath, path.posix.extname(normalizedPath));
  return !/^texture_\d+$/i.test(baseName);
}

function resolveWardrobeTextureCandidates(spec, sourceEntry, config) {
  const configuredTextures = uniqueNormalizedPaths(resolveConfigTextures(config));
  if (spec.expandTextureDirectoriesToWardrobes !== true) {
    return configuredTextures;
  }

  if (configuredTextures.length === 0) {
    return configuredTextures;
  }

  const textureDirectories = Array.from(
    new Set(
      configuredTextures
        .map((texturePath) => path.posix.dirname(texturePath))
        .filter((directory) => directory && directory !== ".")
    )
  );
  if (textureDirectories.length !== 1) {
    return configuredTextures;
  }

  const sourceEntryDirectory = path.posix.dirname(sourceEntry);
  const textureDirectory = textureDirectories[0];
  const absoluteTextureDirectory = path.join(
    activeModelsRoot,
    ...sourceEntryDirectory.split("/"),
    ...textureDirectory.split("/")
  );

  if (!fs.existsSync(absoluteTextureDirectory) || !fs.statSync(absoluteTextureDirectory).isDirectory()) {
    return configuredTextures;
  }

  const discoveredTextures = fs.readdirSync(absoluteTextureDirectory, { withFileTypes: true })
    .filter((entry) => entry.isFile())
    .map((entry) => path.posix.join(textureDirectory, entry.name))
    .filter(isWardrobeTextureCandidate)
    .sort((left, right) => left.localeCompare(right));

  return uniqueNormalizedPaths([
    ...configuredTextures,
    ...discoveredTextures
  ]);
}

function modelEntryPriority(relativePath) {
  const normalizedPath = relativePath.replace(/\\/g, "/");
  const baseName = path.posix.basename(normalizedPath).toLowerCase();
  const depth = normalizedPath.split("/").length;

  if (baseName.endsWith(".model3.json")) {
    return depth * 10;
  }
  if (baseName === "model.json") {
    return depth * 10 + 1;
  }
  if (baseName.endsWith(".model.json")) {
    return depth * 10 + 2;
  }
  if (baseName === "index.json") {
    return depth * 10 + 3;
  }

  return depth * 10 + 9;
}

function discoverModelEntry(dirName) {
  const sourceDirectory = path.join(activeModelsRoot, dirName);
  if (!fs.existsSync(sourceDirectory) || !fs.statSync(sourceDirectory).isDirectory()) {
    throw new Error(`模型目录不存在: ${sourceDirectory}`);
  }

  const candidates = [];
  walkDirectory(sourceDirectory, (filePath) => {
    if (!isModelEntryFile(path.basename(filePath))) {
      return;
    }

    const relativePath = path.relative(activeModelsRoot, filePath).split(path.sep).join("/");
    candidates.push(relativePath);
  });

  if (candidates.length === 0) {
    throw new Error(`模型目录缺少入口文件: ${dirName}`);
  }

  return [...candidates].sort((left, right) => {
    const priorityDifference = modelEntryPriority(left) - modelEntryPriority(right);
    return priorityDifference !== 0 ? priorityDifference : left.localeCompare(right);
  })[0];
}

function collectPresetOverrides(presetDocument) {
  const excludeDirs = new Set(
    (presetDocument.excludeDirs ?? [])
      .map(normalizeDirectoryName)
      .filter(Boolean)
  );
  const overridesByDir = new Map();

  for (const directoryOverride of presetDocument.directories ?? []) {
    const dirName = normalizeDirectoryName(directoryOverride?.dir);
    if (!dirName) {
      throw new Error("目录覆盖项缺少 dir");
    }

    overridesByDir.set(dirName, {
      ...directoryOverride,
      dir: dirName
    });
  }

  return {
    excludeDirs,
    overridesByDir
  };
}

function discoverTopLevelDirectories() {
  return fs.readdirSync(activeModelsRoot, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => entry.name)
    .sort((left, right) => left.localeCompare(right));
}

function createDiscoveredSpec(dirName, override = {}) {
  const entry = typeof override.entry === "string" && override.entry.trim()
    ? override.entry.trim()
    : discoverModelEntry(dirName);
  const resolvedID = normalizeDirectoryName(override.id) || slugifyIdentifier(dirName);
  const resolvedDisplayName = normalizeDirectoryName(override.displayName) || titleCaseLabel(dirName);

  return {
    id: resolvedID,
    displayName: resolvedDisplayName,
    dir: dirName,
    entry,
    ...override,
    id: resolvedID,
    displayName: resolvedDisplayName,
    dir: dirName
  };
}

function buildSelectedModelSpecs(presetDocument) {
  const { excludeDirs, overridesByDir } = collectPresetOverrides(presetDocument);
  const selectedModels = [];
  const seenIDs = new Set();
  const discoveredDirSet = new Set(discoverTopLevelDirectories());

  for (const dirName of discoveredDirSet) {
    if (excludeDirs.has(dirName)) {
      continue;
    }

    const override = overridesByDir.get(dirName) ?? {};
    if (override.hidden === true) {
      continue;
    }

    const spec = registerGeneratedTextureWardrobes(
      registerGeneratedTextureCombinationWardrobes(createDiscoveredSpec(dirName, override))
    );
    if (seenIDs.has(spec.id)) {
      throw new Error(`模型 id 重复: ${spec.id}`);
    }
    seenIDs.add(spec.id);

    selectedModels.push(spec);
  }

  for (const dirName of overridesByDir.keys()) {
    if (!discoveredDirSet.has(dirName)) {
      throw new Error(`目录覆盖项指向了不存在的模型目录: ${dirName}`);
    }
  }

  return selectedModels;
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
  const generatedManifest = generatedManifestEntries.get(entry);
  if (generatedManifest) {
    return generatedManifest.filePath;
  }

  if (entry.includes("/")) {
    return path.join(activeModelsRoot, entry);
  }

  return path.join(activeModelsRoot, spec.dir, entry);
}

function resolveLogicalModelPath(spec, entry) {
  if (entry.includes("/")) {
    return path.posix.join("live2d-models", "oml2d", entry);
  }

  return path.posix.join("live2d-models", "oml2d", spec.dir, entry);
}

function resolveRemotePath(spec, entry) {
  return entry.includes("/") ? entry : path.posix.join(spec.dir, entry);
}

function isSpecAvailable(spec) {
  return resolveEntryList(spec).every((entry) => fs.existsSync(resolveModelConfigPath(spec, entry)));
}

function readModelConfig(spec) {
  const modelPath = resolveModelConfigPath(spec, resolveEntryList(spec)[0]);
  return readJSON(modelPath);
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

function shouldIncludeAsset(filePath) {
  const fileName = path.basename(filePath);
  const normalizedFileName = fileName.toLowerCase();
  if (excludedSuffixes.some((suffix) => normalizedFileName.endsWith(suffix))) {
    return false;
  }

  const extension = path.extname(normalizedFileName);
  return !excludedExtensions.has(extension);
}

function shouldIncludePreview(filePath) {
  const normalizedFilePath = filePath.toLowerCase();
  if (excludedSuffixes.some((suffix) => normalizedFilePath.endsWith(suffix))) {
    return false;
  }

  if (!previewImageExtensions.has(path.extname(normalizedFilePath))) {
    return false;
  }

  const normalizedBaseName = path.basename(normalizedFilePath, path.extname(normalizedFilePath));
  if (/^texture_\d+$/i.test(normalizedBaseName)) {
    return false;
  }
  if (isTextureDirectoryPath(normalizedFilePath)) {
    return false;
  }

  return true;
}

function sha256ForFile(filePath) {
  return crypto.createHash("sha256").update(fs.readFileSync(filePath)).digest("hex");
}

function createAssetEntry(relativeModelPath) {
  if (assetEntryCache.has(relativeModelPath)) {
    return assetEntryCache.get(relativeModelPath);
  }

  const generatedManifest = generatedManifestEntries.get(relativeModelPath);
  const filePath = generatedManifest
    ? generatedManifest.filePath
    : path.join(activeModelsRoot, ...relativeModelPath.split("/"));
  const stats = fs.statSync(filePath);
  const assetEntry = {
    relativePath: path.posix.join("live2d-models", "oml2d", relativeModelPath),
    downloadPath: relativeModelPath,
    size: stats.size,
    sha256: sha256ForFile(filePath)
  };

  if (activeAssetBaseURL) {
    assetEntry.downloadUrl = `${activeAssetBaseURL.replace(/\/$/, "")}/${relativeModelPath}`;
  }

  assetEntryCache.set(relativeModelPath, assetEntry);
  return assetEntry;
}

function collectAssetsForEntry(entry) {
  if (collectedAssetsCache.has(entry)) {
    return collectedAssetsCache.get(entry);
  }

  const generatedManifest = generatedManifestEntries.get(entry);
  if (generatedManifest) {
    const generatedAssets = [
      createAssetEntry(entry),
      ...collectAssetsForEntry(generatedManifest.sourceEntry)
    ];
    collectedAssetsCache.set(entry, generatedAssets);
    return generatedAssets;
  }

  const relativeDirectory = path.posix.dirname(entry);
  const sourceDirectory = path.join(activeModelsRoot, ...relativeDirectory.split("/"));

  if (!fs.existsSync(sourceDirectory) || !fs.statSync(sourceDirectory).isDirectory()) {
    throw new Error(`Model directory not found: ${sourceDirectory}`);
  }

  const result = [];
  walkDirectory(sourceDirectory, (filePath) => {
    if (!shouldIncludeAsset(filePath)) {
      return;
    }

    const relativeToModelsRoot = path.relative(activeModelsRoot, filePath).split(path.sep).join("/");
    result.push(createAssetEntry(relativeToModelsRoot));
  });

  collectedAssetsCache.set(entry, result);
  return result;
}

function walkDirectory(directoryPath, onFile) {
  const entries = fs.readdirSync(directoryPath, { withFileTypes: true });
  for (const entry of entries) {
    const resolvedPath = path.join(directoryPath, entry.name);
    if (entry.isDirectory()) {
      walkDirectory(resolvedPath, onFile);
      continue;
    }
    if (entry.isFile()) {
      onFile(resolvedPath);
    }
  }
}

function deduplicateAssets(assets) {
  const seen = new Set();
  return assets.filter((asset) => {
    if (seen.has(asset.relativePath)) {
      return false;
    }
    seen.add(asset.relativePath);
    return true;
  });
}

function humanizeLabel(source) {
  return String(source ?? "")
    .replace(/\.[^.]+$/, "")
    .replace(/[_-]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function resolveWardrobeLabel(spec, entry, index) {
  const generatedManifest = generatedManifestEntries.get(entry);
  if (generatedManifest?.label) {
    return generatedManifest.label;
  }

  if (Array.isArray(spec.wardrobeLabels)) {
    const candidate = spec.wardrobeLabels[index];
    if (typeof candidate === "string" && candidate.trim()) {
      return candidate.trim();
    }
  }

  if (index === 0) {
    return "默认";
  }

  const entryDirectory = path.posix.dirname(entry);
  const sourceName =
    entryDirectory && entryDirectory !== "."
      ? path.posix.basename(entryDirectory)
      : path.posix.basename(entry, path.posix.extname(entry));

  const humanized = humanizeLabel(sourceName);
  return humanized || `衣装 ${index + 1}`;
}

function scorePreviewCandidate(spec, entry, relativePath) {
  const normalizedRelativePath = relativePath.toLowerCase();
  const normalizedEntry = entry.toLowerCase();
  const candidateDir = path.posix.dirname(normalizedRelativePath);
  const candidateBaseName = path.posix.basename(
    normalizedRelativePath,
    path.posix.extname(normalizedRelativePath)
  );
  const entryDir = path.posix.dirname(normalizedEntry);
  const entryBaseName = path.posix.basename(normalizedEntry, path.posix.extname(normalizedEntry));
  const modelDirName =
    entryDir && entryDir !== "."
      ? path.posix.basename(entryDir)
      : String(spec.dir ?? "").trim().toLowerCase();

  let score = 0;

  if (previewKeywords.some((keyword) => candidateBaseName.includes(keyword))) {
    score += 140;
  }
  if (candidateDir === entryDir || candidateDir === ".") {
    score += 90;
  }
  if (candidateBaseName === modelDirName || candidateBaseName === entryBaseName) {
    score += 80;
  }
  if (candidateBaseName.includes(modelDirName) || candidateBaseName.includes(entryBaseName)) {
    score += 48;
  }
  if (candidateBaseName.includes("default")) {
    score += 42;
  }
  if (path.posix.extname(normalizedRelativePath) === ".png") {
    score += 12;
  }
  if (normalizedRelativePath.includes("/textures/")) {
    score -= 18;
  }

  return score;
}

function resolvePreviewPathForEntry(spec, entry) {
  const generatedManifest = generatedManifestEntries.get(entry);
  if (generatedManifest?.previewPath) {
    return generatedManifest.previewPath;
  }

  const previewEntry = generatedManifest?.sourceEntry
    ? resolveRemotePath(spec, generatedManifest.sourceEntry)
    : entry;
  const relativeDirectory = path.posix.dirname(previewEntry);
  const sourceDirectory = path.join(activeModelsRoot, ...relativeDirectory.split("/"));

  if (!fs.existsSync(sourceDirectory) || !fs.statSync(sourceDirectory).isDirectory()) {
    return null;
  }

  const candidates = [];
  walkDirectory(sourceDirectory, (filePath) => {
    if (!shouldIncludePreview(filePath)) {
      return;
    }

    candidates.push(path.relative(activeModelsRoot, filePath).split(path.sep).join("/"));
  });

  if (candidates.length === 0) {
    const fallbackEntry = generatedManifest?.sourceEntry
      ? resolveRemotePath(spec, generatedManifest.sourceEntry)
      : previewEntry;
    const fallbackConfig = readJSON(resolveModelConfigPath(spec, fallbackEntry));
    const fallbackTextures = uniqueNormalizedPaths(resolveConfigTextures(fallbackConfig));
    if (fallbackTextures.length === 0) {
      return null;
    }

    return path.posix.join(path.posix.dirname(fallbackEntry), fallbackTextures[0]);
  }

  return [...candidates].sort((left, right) => {
    const scoreDifference = scorePreviewCandidate(spec, entry, right) - scorePreviewCandidate(spec, entry, left);
    return scoreDifference !== 0 ? scoreDifference : left.localeCompare(right);
  })[0];
}

function buildWardrobes(spec) {
  return resolveEntryList(spec).map((entry, index) => ({
    id: `${spec.id}:${index + 1}`,
    label: resolveWardrobeLabel(spec, entry, index),
    modelPath: resolveLogicalModelPath(spec, entry),
    previewPath: resolvePreviewPathForEntry(spec, resolveRemotePath(spec, entry))
  }));
}

function createCharacterEntry(spec) {
  const config = readModelConfig(spec);
  const motionGroups = motionGroupsFromConfig(config);
  const modelPaths = resolveEntryList(spec).map((entry) => resolveLogicalModelPath(spec, entry));
  const position = resolvePosition(spec);
  const anchor = resolveAnchor(spec);
  const stageStyle = resolveStageStyle(spec);
  const wardrobes = buildWardrobes(spec);
  const previewPath = wardrobes.find((item) => {
    const candidatePath = String(item.previewPath ?? "");
    return candidatePath && !isTextureDirectoryPath(candidatePath);
  })?.previewPath
    ?? wardrobes.find((item) => String(item.previewPath ?? "").trim())?.previewPath
    ?? null;

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
      previewPath,
      wardrobes,
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

function buildCatalogItem(spec) {
  const character = createCharacterEntry(spec);
  const assets = deduplicateAssets(
    resolveEntryList(spec)
      .map((entry) => resolveRemotePath(spec, entry))
      .flatMap((entry) => collectAssetsForEntry(entry))
  ).sort((left, right) => left.relativePath.localeCompare(right.relativePath));

  const version = crypto.createHash("sha256").update(
    JSON.stringify({
      character,
      assets: assets.map((asset) => ({
        relativePath: asset.relativePath,
        sha256: asset.sha256,
        size: asset.size
      }))
    })
  ).digest("hex").slice(0, 12);

  return {
    id: spec.id,
    version,
    character,
    install: {
      assets
    }
  };
}

function writeJSON(targetPath, payload) {
  fs.mkdirSync(path.dirname(targetPath), { recursive: true });
  fs.writeFileSync(targetPath, `${JSON.stringify(payload, null, 2)}\n`);
}

function buildBundledCharacterLibrary() {
  return {
    defaultCharacterId: "dewy-lime",
    characters: [spriteCharacter]
  };
}

function buildLive2DCatalog(selectedModels) {
  return {
    version: catalogVersion,
    generatedAt: new Date().toISOString(),
    ...(activeAssetBaseURL ? { assetBaseURL: activeAssetBaseURL } : {}),
    items: selectedModels.map(buildCatalogItem)
  };
}

function writeTargets(targets, payload) {
  for (const target of targets) {
    if (target.includes(`${path.sep}limecore${path.sep}`) && !fs.existsSync(path.dirname(target))) {
      continue;
    }
    writeJSON(target, payload);
  }
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  const presetsPath = assertReadableFile(options.presetsPath, "模型预设文件");
  activeModelsRoot = assertReadableDirectory(options.modelsRoot, "Live2D 模型目录");
  activeAssetBaseURL = String(options.assetBaseURL ?? "").trim();

  const presetDocument = normalizePresetDocument(readJSON(presetsPath));
  const discoveredModels = buildSelectedModelSpecs(presetDocument);
  const selectedModels = [];
  const skippedOptionalModels = [];

  for (const spec of discoveredModels) {
    if (isSpecAvailable(spec)) {
      selectedModels.push(spec);
      continue;
    }

    if (spec.optional) {
      skippedOptionalModels.push(spec.id);
      continue;
    }

    throw new Error(`模型预设缺少源文件: ${spec.id}`);
  }

  const bundledCharacterLibrary = buildBundledCharacterLibrary();
  const live2dCatalog = buildLive2DCatalog(selectedModels);

  if (options.dryRun) {
    console.log(
      `Dry run: ${selectedModels.length} 个可安装模型，模型目录 ${activeModelsRoot}`
    );
    return;
  }

  if (!options.skipCharacterLibrary) {
    writeTargets(options.characterLibraryTargets, bundledCharacterLibrary);
  }

  if (!options.skipCatalog) {
    writeTargets(options.catalogTargets, live2dCatalog);
  }

  console.log(
    `Generated bundled character library with ${bundledCharacterLibrary.characters.length} built-in character and ${live2dCatalog.items.length} installable Live2D models`
  );
  if (skippedOptionalModels.length > 0) {
    console.log(
      `Skipped optional models: ${skippedOptionalModels.join(", ")}`
    );
  }
}

const directRunTarget = process.argv[1] ? path.resolve(process.argv[1]) : "";
if (directRunTarget === fileURLToPath(import.meta.url)) {
  try {
    main();
  } catch (error) {
    console.error(
      error instanceof Error ? error.message : String(error)
    );
    process.exit(1);
  }
}
