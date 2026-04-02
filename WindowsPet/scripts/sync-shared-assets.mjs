import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const currentDir = path.dirname(fileURLToPath(import.meta.url));
const projectRoot = path.resolve(currentDir, "..");
const repoRoot = path.resolve(projectRoot, "..");
const sourceDir = path.join(repoRoot, "LimePet", "Resources");
const outputDir = path.join(projectRoot, "src", "assets", "shared");
const publicDir = path.join(projectRoot, "public");

const sharedFiles = [
  "dewy-lime-shadow.png",
  "dewy-lime-cutout.png",
  "dewy-lime.png",
  "character-library.json"
];

const sharedDirectories = [
  "live2d-runtime",
  "live2d-models"
];

fs.mkdirSync(outputDir, { recursive: true });
fs.mkdirSync(publicDir, { recursive: true });

for (const fileName of sharedFiles) {
  const sourcePath = path.join(sourceDir, fileName);
  const outputPath = path.join(outputDir, fileName);
  fs.copyFileSync(sourcePath, outputPath);
}

for (const directoryName of sharedDirectories) {
  const sourcePath = path.join(sourceDir, directoryName);
  const outputPath = path.join(publicDir, directoryName);
  fs.rmSync(outputPath, { recursive: true, force: true });
  fs.cpSync(sourcePath, outputPath, { recursive: true });
}

console.log(
  `Synced ${sharedFiles.length} shared files and ${sharedDirectories.length} shared directories`,
);
