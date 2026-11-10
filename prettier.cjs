const path = require("node:path");
const os = require("node:os");

const globalActive = path.join(os.homedir(), "Library/pnpm/global-active");
const qualityGatesPackageRoot = path.join(__dirname, ".github/quality-gates");

// CIと同じ固定版を使うため、QualityGates package rootを最初に試す。
// 素のrequire.resolveを先にすると、NODE_PATHのpnpm global（別版）が優先され判定が食い違う。
function resolvePlugin(name, fallback) {
  try {
    return require.resolve(name, { paths: [qualityGatesPackageRoot] });
  } catch {
    try {
      return require.resolve(name);
    } catch {
      return path.join(globalActive, fallback);
    }
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
      files: "*.json",
      options: {
        printWidth: 1,
      },
    },
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
