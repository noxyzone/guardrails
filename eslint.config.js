import path from "node:path";
import { createRequire } from "node:module";

const projectRequire = createRequire(path.join(process.cwd(), "package.json"));

function optionalRequire(name) {
  try {
    return projectRequire(name);
  } catch (_error) {
    return null;
  }
}

const tsParser = optionalRequire("@typescript-eslint/parser");
const tsPlugin = optionalRequire("@typescript-eslint/eslint-plugin");

const config = [
  {
    ignores: [
      "**/.astro/**",
      "**/.next/**",
      "**/dist/**",
      "**/node_modules/**",
      ".agents/skills/aidlc*/**",
      ".codex/agents/aidlc-*/**",
      ".codex/aidlc-common/**",
      ".codex/hooks/aidlc-*",
      ".codex/knowledge/aidlc-*/**",
      ".codex/scopes/aidlc-*/**",
      ".codex/sensors/aidlc-*",
      ".codex/tools/aidlc-*",
      ".codex/tools/data/**",
      "aidlc/spaces/**",
    ],
  },
  {
    files: ["**/*.cjs"],
    languageOptions: {
      ecmaVersion: "latest",
      sourceType: "commonjs",
    },
  },
  {
    files: ["**/*.{js,mjs}"],
    languageOptions: {
      ecmaVersion: "latest",
      sourceType: "module",
    },
  },
];

if (tsParser && tsPlugin) {
  config.push({
    files: ["**/*.ts"],
    languageOptions: {
      ecmaVersion: "latest",
      parser: tsParser,
      sourceType: "module",
    },
    plugins: {
      "@typescript-eslint": tsPlugin,
    },
    rules: {
      ...tsPlugin.configs.recommended.rules,
    },
  });
} else {
  config.push({
    ignores: ["**/*.ts"],
  });
}

export default config;
