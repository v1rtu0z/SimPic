const { withGradleProperties, withAppBuildGradle } = require('@expo/config-plugins');

const withBuildConfig = (config) => {
    // Fix 1: Set minSdkVersion and Hermes in gradle.properties
    config = withGradleProperties(config, (config) => {
        // Remove existing entries
        config.modResults = config.modResults.filter(
            item => item.type !== 'property' ||
                (item.key !== 'android.minSdkVersion' && item.key !== 'expo.jsEngine')
        );

        // Add minSdkVersion = 26
        config.modResults.push({
            type: 'property',
            key: 'android.minSdkVersion',
            value: '26',
        });

        // Add expo.jsEngine = hermes
        config.modResults.push({
            type: 'property',
            key: 'expo.jsEngine',
            value: 'hermes',
        });

        return config;
    });

    // Fix 2: Modify app/build.gradle - add hermesEnabled, buildFeatures, remove JSC
    config = withAppBuildGradle(config, (config) => {
        let contents = config.modResults.contents;

        // Add hermesEnabled = true at the top if not present
        if (!contents.includes('def hermesEnabled')) {
            contents = contents.replace(
                /(apply plugin: "com\.facebook\.react"\s*)/,
                `$1\ndef hermesEnabled = true\n`
            );
        }

        // Add buildFeatures if not present
        if (!contents.includes('buildFeatures')) {
            contents = contents.replace(
                /(android\s*\{)/,
                `$1\n    buildFeatures {\n        buildConfig = true\n    }\n`
            );
        }

        // Remove JSC flavor definition (the comment block and the def line)
        contents = contents.replace(
            /\/\*\*\s*\n\s*\* The preferred build flavor[\s\S]*?\*\/\s*\ndef jscFlavor = '[^']+'\s*\n/,
            ''
        );

        // Force Hermes by replacing the conditional dependency
        contents = contents.replace(
            /if \(hermesEnabled\.toBoolean\(\)\) \{\s*implementation\("com\.facebook\.react:hermes-android"\)\s*\} else \{\s*implementation jscFlavor\s*\}/,
            '// Force Hermes - JSC removed by config plugin\n    implementation("com.facebook.react:hermes-android")'
        );

        config.modResults.contents = contents;
        return config;
    });

    return config;
};

module.exports = withBuildConfig;