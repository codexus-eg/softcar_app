const fs = require("fs");
const path = require("path");
const staticConfig = require("./app.json").expo;

function readRootEnv(name) {
  try {
    const envPath = path.resolve(__dirname, "..", ".env");
    const line = fs
      .readFileSync(envPath, "utf8")
      .split(/\r?\n/)
      .find((entry) => entry.trim().startsWith(`${name}=`));
    if (!line) return "";
    return line
      .slice(line.indexOf("=") + 1)
      .trim()
      .replace(/^['"]|['"]$/g, "");
  } catch {
    return "";
  }
}

module.exports = ({ config }) => {
  const base = {
    ...config,
    ...staticConfig,
    ios: { ...config.ios, ...staticConfig.ios },
    android: { ...config.android, ...staticConfig.android },
    extra: { ...config.extra, ...staticConfig.extra },
  };
  const mapsKey =
    process.env.EXPO_PUBLIC_GOOGLE_MAPS_API_KEY ||
    process.env.NEXT_PUBLIC_GOOGLE_MAPS_API_KEY ||
    readRootEnv("NEXT_PUBLIC_GOOGLE_MAPS_API_KEY") ||
    "";
  return {
    ...base,
    ios: {
      ...base.ios,
      ...(mapsKey ? { config: { googleMapsApiKey: mapsKey } } : {}),
    },
    android: {
      ...base.android,
      ...(mapsKey ? { config: { googleMaps: { apiKey: mapsKey } } } : {}),
    },
    extra: {
      ...base.extra,
      googleMapsApiKey: mapsKey,
    },
  };
};
