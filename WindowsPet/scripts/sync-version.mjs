import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const currentDir = path.dirname(fileURLToPath(import.meta.url));
const projectRoot = path.resolve(currentDir, "..");

const version = process.argv[2]?.trim().replace(/^v/, "");

if (!version) {
  console.error("请提供版本号，例如 0.3.3 或 v0.3.3");
  process.exit(1);
}

const packageJsonPath = path.join(projectRoot, "package.json");
const tauriConfigPath = path.join(projectRoot, "src-tauri", "tauri.conf.json");
const cargoTomlPath = path.join(projectRoot, "src-tauri", "Cargo.toml");

const packageJson = JSON.parse(fs.readFileSync(packageJsonPath, "utf8"));
packageJson.version = version;
fs.writeFileSync(packageJsonPath, JSON.stringify(packageJson, null, 2) + "\n", "utf8");

const tauriConfig = JSON.parse(fs.readFileSync(tauriConfigPath, "utf8"));
tauriConfig.version = version;
fs.writeFileSync(tauriConfigPath, JSON.stringify(tauriConfig, null, 2) + "\n", "utf8");

const cargoToml = fs.readFileSync(cargoTomlPath, "utf8");
const updatedCargoToml = cargoToml.replace(
  /^version = ".*"$/m,
  `version = "${version}"`
);
fs.writeFileSync(cargoTomlPath, updatedCargoToml, "utf8");

console.log(`Synced Windows companion version to ${version}`);
