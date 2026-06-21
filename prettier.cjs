const path = require("node:path");
const os = require("node:os");

const globalActive = path.join(os.homedir(), "Library/pnpm/global-active");

function resolvePlugin(name, fallback) {
  try {
    return require.resolve(name);
  } catch (_error) {
    return path.join(globalActive, fallback);
  }
}

module.exports = {
  plugins: [
    resolvePlugin("@prettier/plugin-xml", "@prettier/plugin-xml/src/plugin.js"),
    resolvePlugin(
      "prettier-plugin-go-template",
      "prettier-plugin-go-template/lib/index.js",
    ),
    resolvePlugin("prettier-plugin-sh", "prettier-plugin-sh/lib/index.cjs"),
    resolvePlugin("prettier-plugin-toml", "prettier-plugin-toml/lib/index.cjs"),
  ],
  overrides: [
    {
      files: "*.html",
      options: {
        parser: "go-template",
      },
    },
    {
      files: ["*.xcstrings", "*.xctestplan"],
      options: {
        parser: "json",
      },
    },
    {
      files: [
        "*.entitlements",
        "*.plist",
        "*.xcscheme",
        "*.xcworkspacedata",
        "*.xml",
        "*.xsd",
      ],
      options: {
        parser: "xml",
        xmlWhitespaceSensitivity: "ignore",
      },
    },
  ],
};
