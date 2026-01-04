module.exports = {
    expo: {
        jsEngine: "hermes",
        developmentClient: {
            silentLaunch: true
        },
        name: "SimPic - AI Photo Coach",
        slug: "simpic",
        version: "1.0.0",
        orientation: "portrait",
        icon: "./assets/icon.png",
        userInterfaceStyle: "light",
        splash: {
            image: "./assets/splash.png",
            resizeMode: "contain",
            backgroundColor: "#000000"
        },
        assetBundlePatterns: ["**/*"],
        ios: {
            supportsTablet: true,
            infoPlist: {
                NSCameraUsageDescription: "SimPic needs access to your camera to take photos.",
                NSPhotoLibraryUsageDescription: "SimPic needs access to your photo library to save photos.",
                NSPhotoLibraryAddUsageDescription: "SimPic needs permission to save photos to your gallery."
            },
            bundleIdentifier: "com.simpic.coach"
        },
        android: {
            adaptiveIcon: {
                foregroundImage: "./assets/adaptive-icon.png",
                backgroundColor: "#000000"
            },
            permissions: [
                "android.permission.CAMERA",
                "android.permission.READ_MEDIA_IMAGES",
                "android.permission.WRITE_EXTERNAL_STORAGE"
            ],
            package: "com.simpic.coach"
        },
        web: {
            favicon: "./assets/favicon.png"
        },
        plugins: [
            [
                "expo-media-library",
                {
                    photosPermission: "Allow SimPic to save photos to your gallery.",
                    savePhotosPermission: "Allow SimPic to save photos to your gallery."
                }
            ],
            [
                "react-native-vision-camera",
                {
                    cameraPermissionText: "SimPic needs access to your camera to take photos.",
                    enableMicrophonePermission: false
                }
            ],
            "./plugins/withBuildConfig"  // Single plugin that does everything!
        ]
    }
};