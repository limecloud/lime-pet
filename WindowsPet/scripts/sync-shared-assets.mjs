import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const currentDir = path.dirname(fileURLToPath(import.meta.url));
const projectRoot = path.resolve(currentDir, "..");
const repoRoot = path.resolve(projectRoot, "..");
const sourceDir = path.join(repoRoot, "LimePet", "Resources");
const outputDir = path.join(projectRoot, "src", "assets", "shared");

const sharedFiles = [
  "dewy-lime-shadow.png",
  "dewy-lime-cutout.png",
  "dewy-lime.png",
  "character-library.json"
];

fs.mkdirSync(outputDir, { recursive: true });

for (const fileName of sharedFiles) {
  const sourcePath = path.join(sourceDir, fileName);
  const outputPath = path.join(outputDir, fileName);
  fs.copyFileSync(sourcePath, outputPath);
}

console.log(`Synced ${sharedFiles.length} shared Lime Pet assets`);
