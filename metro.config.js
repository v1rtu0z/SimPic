const { getDefaultConfig } = require('expo/metro-config');

const config = getDefaultConfig(__dirname);
config.transformer.enableBabelRCLookup = false;

module.exports = config;
