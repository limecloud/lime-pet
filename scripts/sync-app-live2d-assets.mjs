#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const currentDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(currentDir, "..");

const options = parseArgs(process.argv.slice(2), {
  source: path.join(repoRoot, "LimePet", "Resources", "live2d-models"),
  target: "",
  catalog: path.join(repoRoot, "LimePet", "Resources", "character-library.json")
});

if (!options.target) {
  console.error("缺少必要参数: --target");
  process.exit(1);
}

const sourceRoot = path.resolve(options.source);
const targetRoot = path.resolve(options.target);
const catalogPath = path.resolve(options.catalog);
const catalog = JSON.parse(fs.readFileSync(catalogPath, "utf8"));
const directories = collectReferencedDirectories(catalog);

fs.rmSync(targetRoot, { recursive: true, force: true });
fs.mkdirSync(targetRoot, { recursive: true });

for (const relativeDirectory of directories) {
  copyDirectory(sourceRoot, targetRoot, relativeDirectory);
}

console.log(`Synced ${directories.length} Live2D model directories into ${targetRoot}`);

function parseArgs(argv, defaults) {
  const parsed = { ...defaults };

  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--source") {
      parsed.source = readNextValue(argv, index, argument);
      index += 1;
      continue;
    }

    if (argument === "--target") {
      parsed.target = readNextValue(argv, index, argument);
      index += 1;
      continue;
    }

    if (argument === "--catalog") {
      parsed.catalog = readNextValue(argv, index, argument);
      index += 1;
      continue;
    }

    console.error(`未知参数: ${argument}`);
    process.exit(1);
  }

  return parsed;
}

function readNextValue(argv, index, flag) {
  const value = argv[index + 1];
  if (!value) {
    console.error(`参数 ${flag} 缺少取值`);
    process.exit(1);
  }

  return value;
}

function collectReferencedDirectories(catalog) {
  if (!catalog || !Array.isArray(catalog.characters)) {
    throw new Error("character-library.json 缺少 characters 数组");
  }

  const directorySet = new Set();

  for (const character of catalog.characters) {
    const live2d = character?.live2d;
    if (!live2d || typeof live2d !== "object") {
      continue;
    }

    const paths = [];
    if (typeof live2d.modelPath === "string" && live2d.modelPath.length > 0) {
      paths.push(live2d.modelPath);
    }

    if (Array.isArray(live2d.modelPaths)) {
      for (const candidate of live2d.modelPaths) {
        if (typeof candidate === "string" && candidate.length > 0) {
          paths.push(candidate);
        }
      }
    }

    for (const modelPath of paths) {
      const relativeDirectory = resolveDirectory(modelPath);
      if (relativeDirectory) {
        directorySet.add(relativeDirectory);
      }
    }
  }

  return [...directorySet].sort((left, right) => left.localeCompare(right));
}

function resolveDirectory(modelPath) {
  const normalizedPath = modelPath.replace(/\\/g, "/");
  const prefix = "live2d-models/";
  if (!normalizedPath.startsWith(prefix)) {
    return null;
  }

  const relativePath = path.posix.normalize(normalizedPath.slice(prefix.length));
  if (
    relativePath.length === 0 ||
    relativePath === "." ||
    relativePath === ".." ||
    path.posix.isAbsolute(relativePath) ||
    relativePath.startsWith("../")
  ) {
    throw new Error(`非法模型路径: ${modelPath}`);
  }

  const directory = path.posix.dirname(relativePath);
  return directory === "." ? null : directory;
}

function copyDirectory(sourceRootPath, targetRootPath, relativeDirectory) {
  const sourcePath = path.join(sourceRootPath, ...relativeDirectory.split("/"));
  if (!fs.existsSync(sourcePath) || !fs.statSync(sourcePath).isDirectory()) {
    throw new Error(`未找到模型目录: ${sourcePath}`);
  }

  const targetPath = path.join(targetRootPath, ...relativeDirectory.split("/"));
  fs.mkdirSync(path.dirname(targetPath), { recursive: true });
  fs.cpSync(sourcePath, targetPath, { recursive: true });
}
