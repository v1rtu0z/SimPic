import React, {useEffect, useRef, useState} from 'react';
import {
    Alert,
    Animated,
    AppState,
    AppStateStatus,
    Dimensions,
    Image,
    StyleSheet,
    Text,
    TouchableOpacity,
    View,
} from 'react-native';
import {useFaceDetector} from 'react-native-vision-camera-face-detector';
import {Camera, useCameraDevice, useCameraPermission, useFrameProcessor,} from 'react-native-vision-camera';
import * as MediaLibrary from 'expo-media-library';
import * as Sharing from 'expo-sharing';
import * as IntentLauncher from 'expo-intent-launcher';
import {runOnJS} from 'react-native-reanimated';

const {width: SCREEN_WIDTH, height: SCREEN_HEIGHT} = Dimensions.get('window');

// this would need to print hermes for frame processor to work
console.log(
    'JS engine:',
    (globalThis as any).nativeCallSyncHook ? 'Hermes' : 'JSC'
);


export default function CameraScreen() {
    const {hasPermission: hasCameraPermission, requestPermission: requestCameraPermission} = useCameraPermission();
    const [hasMediaLibraryPermission, setHasMediaLibraryPermission] = useState<boolean | null>(null);
    const [isCapturing, setIsCapturing] = useState(false);
    const [lastPhotoUri, setLastPhotoUri] = useState<string | null>(null);
    const [lastAssetId, setLastAssetId] = useState<string | null>(null);
    const [focusPoint, setFocusPoint] = useState<{ x: number, y: number } | null>(null);
    const [isAppActive, setIsAppActive] = useState(true);
    const [cameraError, setCameraError] = useState<string | null>(null);

    const device = useCameraDevice('back');
    const cameraRef = useRef<Camera>(null);
    const lastForegroundTime = useRef<number>(0);

    const thumbnailAnim = useRef(new Animated.Value(0)).current;
    const captureAnim = useRef(new Animated.Value(0)).current;
    const focusAnim = useRef(new Animated.Value(0)).current;

    // const [faces, setFaces] = useState<any[]>([]);
    //
    // const faceDetector = useFaceDetector({
    //     performanceMode: 'fast',
    // });
    //
    // const FRAME_SKIP = 5; // process ~6 FPS on 30fps camera
    //
    // const frameCounter = useRef(0);
    //
    // const frameProcessor = useFrameProcessor((frame) => {
    //     'worklet';
    //
    //     frameCounter.current++;
    //
    //     if (frameCounter.current % FRAME_SKIP !== 0) {
    //         return;
    //     }
    //
    //     const detectedFaces = faceDetector.detectFaces(frame);
    //
    //     // Extract only the serializable bounds data
    //     const faceBounds = detectedFaces.map(face => ({
    //         bounds: {
    //             x: face.bounds.x,
    //             y: face.bounds.y,
    //             width: face.bounds.width,
    //             height: face.bounds.height
    //         }
    //     }));
    //
    //     runOnJS(setFaces)(faceBounds);
    // }, []);

    useEffect(() => {
        checkPermissions();

        const subscription = AppState.addEventListener('change', (nextAppState: AppStateStatus) => {
            console.log('[APP_STATE] App state changed to:', nextAppState);
            setIsAppActive(nextAppState === 'active');
            // Clear error and refresh thumbnail on foregrounding
            if (nextAppState === 'active') {
                lastForegroundTime.current = Date.now();
                setCameraError(null);
                loadLatestPhoto();
            }
        });

        return () => {
            subscription.remove();
        };
    }, []);

    const checkPermissions = async () => {
        if (!hasCameraPermission) {
            await requestCameraPermission();
        }

        const mediaLibraryPermission = await MediaLibrary.requestPermissionsAsync();
        setHasMediaLibraryPermission(mediaLibraryPermission.status === 'granted');

        if (mediaLibraryPermission.status === 'granted') {
            loadLatestPhoto();
        }
    };

    const loadLatestPhoto = async () => {
        try {
            const assets = await MediaLibrary.getAssetsAsync({
                first: 1,
                sortBy: [MediaLibrary.SortBy.creationTime],
                mediaType: [MediaLibrary.MediaType.photo],
            });

            if (assets.assets && assets.assets.length > 0) {
                setLastPhotoUri(assets.assets[0].uri);
                setLastAssetId(assets.assets[0].id);
                thumbnailAnim.setValue(1);
            } else {
                setLastPhotoUri(null);
                setLastAssetId(null);
                thumbnailAnim.setValue(0);
            }
        } catch (error) {
            console.error('Error loading latest photo', error);
        }
    };

    const takePicture = async () => {
        if (!cameraRef.current || isCapturing) return;

        try {
            setIsCapturing(true);

            const photo = await cameraRef.current.takePhoto({
                flash: 'off',
                enableShutterSound: true,
            });

            const photoUri = `file://${photo.path}`;

            if (hasMediaLibraryPermission) {
                // Save to gallery using MediaLibrary
                const asset = await MediaLibrary.createAssetAsync(photoUri);
                setLastPhotoUri(photoUri);
                setLastAssetId(asset.id);

                // Start "Fly-to-Corner" animation
                captureAnim.setValue(0);
                thumbnailAnim.setValue(0);

                Animated.parallel([
                    Animated.timing(captureAnim, {
                        toValue: 1,
                        duration: 500,
                        useNativeDriver: true,
                    }),
                    Animated.spring(thumbnailAnim, {
                        toValue: 1,
                        delay: 400,
                        useNativeDriver: true,
                        tension: 20,
                        friction: 7,
                    })
                ]).start();
            } else {
                Alert.alert('Permission Required', 'Please grant media library permission to save photos.');
            }
        } catch (error) {
            console.error('Error taking picture:', error);
            Alert.alert('Error', 'Failed to save photo');
        } finally {
            setIsCapturing(false);
        }
    };

    const openLastPhoto = async () => {
        if (lastPhotoUri && lastAssetId) {
            try {
                // On Android, we can construct a direct "content://" URI using the asset ID.
                // This is the absolute most reliable way to open a gallery photo directly
                // while allowing swiping, without hitting "FileUriExposedException".
                const contentUri = `content://media/external/images/media/${lastAssetId}`;

                await IntentLauncher.startActivityAsync('android.intent.action.VIEW', {
                    data: contentUri,
                    type: 'image/jpeg',
                    flags: 1, // FLAG_GRANT_READ_URI_PERMISSION
                });
            } catch (error) {
                console.error('Failed to launch gallery intent', error);
                // Final fallback: try to share the raw URI
                await Sharing.shareAsync(lastPhotoUri);
            }
        } else if (lastPhotoUri) {
            // Fallback if we don't have asset ID for some reason
            await Sharing.shareAsync(lastPhotoUri);
        }
    };

    const handleTapToFocus = async (event: any) => {
        const {locationX, locationY} = event.nativeEvent;

        // Set the focus point for the UI (pixels)
        setFocusPoint({x: locationX, y: locationY});

        if (cameraRef.current) {
            try {
                console.log(`[FOCUS_DEBUG] Attempting focus at: ${locationX}, ${locationY}`);
                await cameraRef.current.focus({x: locationX, y: locationY});
            } catch (e) {
                console.error('[FOCUS_DEBUG] Focus failed:', e);
            }
        }

        // Animate the focus ring
        focusAnim.setValue(0);
        Animated.sequence([
            Animated.timing(focusAnim, {
                toValue: 1,
                duration: 150,
                useNativeDriver: true,
            }),
            Animated.delay(500),
            Animated.timing(focusAnim, {
                toValue: 0,
                duration: 150,
                useNativeDriver: true,
            }),
        ]).start(() => setFocusPoint(null));
    };

    if (!hasCameraPermission) {
        return (
            <View style={styles.container}>
                <Text style={styles.text}>Camera permission is required.</Text>
                <TouchableOpacity style={styles.button} onPress={requestCameraPermission}>
                    <Text style={styles.buttonText}>Grant Permission</Text>
                </TouchableOpacity>
            </View>
        );
    }

    if (device == null) {
        return (
            <View style={styles.container}>
                <Text style={styles.text}>No camera device found</Text>
            </View>
        );
    }

    const showRestrictedAlert = () => {
        Alert.alert(
            'Camera Restricted',
            'Camera access is restricted. This usually happens because:\n\n' +
            '1. Another app (Zoom, WhatsApp, etc.) is using the camera.\n' +
            '2. "Camera Access" is turned OFF in your Android Quick Settings.\n' +
            '3. Your device has a Work Profile/MDM policy restricting camera use.\n\n' +
            'Please check these and restart the app.',
            [
                {
                    text: 'How to fix', onPress: () => {
                        Alert.alert('Troubleshooting', '• Pull down your notification bar and look for a "Camera Access" toggle.\n• Close all background apps.\n• If this is a work phone, contact your IT admin.');
                    }
                },
                {text: 'OK'}
            ]
        );
    };

    if (cameraError === 'system/camera-is-restricted') {
        return (
            <View style={styles.container}>
                <Text style={styles.text}>Camera is Restricted</Text>
                <Text style={styles.subText}>The system is preventing access to the camera.</Text>
                <TouchableOpacity style={styles.button} onPress={showRestrictedAlert}>
                    <Text style={styles.buttonText}>Troubleshoot</Text>
                </TouchableOpacity>
                <TouchableOpacity style={[styles.button, {marginTop: 20, backgroundColor: '#444'}]}
                                  onPress={() => setCameraError(null)}>
                    <Text style={styles.buttonText}>Retry</Text>
                </TouchableOpacity>
            </View>
        );
    }

    return (
        <View style={styles.container}>
            <TouchableOpacity
                activeOpacity={1}
                style={styles.cameraContainer}
                onPress={handleTapToFocus}
            >
                <Camera
                    ref={cameraRef}
                    style={styles.camera}
                    device={device}
                    isActive={isAppActive}
                    photo={true}
                    // frameProcessor={frameProcessor}
                    enableZoomGesture={true}
                    onError={(error) => {
                        console.error('Camera Error:', error);
                        // Only show the restricted UI if it's a persistent error.
                        // Some devices report this transiently when switching back from gallery.
                        if (error.code === 'system/camera-is-restricted') {
                            const timeSinceForeground = Date.now() - lastForegroundTime.current;
                            // If we just foregrounded in the last 2 seconds, ignore transient restriction errors
                            if (timeSinceForeground < 2000) {
                                console.log('[CAMERA_DEBUG] Ignoring transient restriction error during foregrounding');
                                return;
                            }
                            setCameraError(error.code);
                        }
                    }}
                />
            </TouchableOpacity>

            {/* Overlays (placed after CameraView to be on top) */}
            <View style={StyleSheet.absoluteFill} pointerEvents="none">
                <View style={styles.statusContainer}>
                    <Text style={styles.statusText}>Dev Mode Active</Text>
                </View>

                {/*{faces.map((face, index) => {*/}
                {/*    const {x, y, width, height} = face.bounds;*/}

                {/*    return (*/}
                {/*        <View*/}
                {/*            key={`face-${index}`}*/}
                {/*            style={[*/}
                {/*                styles.faceBox,*/}
                {/*                {*/}
                {/*                    left: x,*/}
                {/*                    top: y,*/}
                {/*                    width,*/}
                {/*                    height,*/}
                {/*                },*/}
                {/*            ]}*/}
                {/*        />*/}
                {/*    );*/}
                {/*})}*/}

                {/* Focus Ring */}
                {focusPoint && (
                    <Animated.View
                        style={[
                            styles.focusRing,
                            {
                                left: focusPoint.x - 40,
                                top: focusPoint.y - 40,
                                opacity: focusAnim,
                                transform: [
                                    {
                                        scale: focusAnim.interpolate({
                                            inputRange: [0, 1],
                                            outputRange: [1.5, 1]
                                        })
                                    }
                                ]
                            }
                        ]}
                    />
                )}
            </View>

            {/* Fly-to-corner animation overlay */}
            {lastPhotoUri && (
                <Animated.View
                    pointerEvents="none"
                    style={[
                        styles.captureAnimationOverlay,
                        {
                            opacity: captureAnim.interpolate({
                                inputRange: [0, 0.1, 0.9, 1],
                                outputRange: [0, 1, 1, 0],
                            }),
                            transform: [
                                {
                                    translateX: captureAnim.interpolate({
                                        inputRange: [0, 1],
                                        outputRange: [0, -SCREEN_WIDTH / 2 + 50],
                                    }),
                                },
                                {
                                    translateY: captureAnim.interpolate({
                                        inputRange: [0, 1],
                                        outputRange: [0, SCREEN_HEIGHT / 2 - 80],
                                    }),
                                },
                                {
                                    scale: captureAnim.interpolate({
                                        inputRange: [0, 1],
                                        outputRange: [0.8, 0.1],
                                    }),
                                },
                            ],
                        },
                    ]}
                >
                    <Image source={{uri: lastPhotoUri}} style={styles.fullImage}/>
                </Animated.View>
            )}

            {/* Capture Button */}
            <View style={styles.controlsContainer}>
                {/* Thumbnail Preview */}
                <TouchableOpacity
                    style={styles.thumbnailContainer}
                    onPress={openLastPhoto}
                >
                    {lastPhotoUri ? (
                        <Animated.View style={{
                            opacity: thumbnailAnim,
                            transform: [
                                {
                                    scale: thumbnailAnim.interpolate({
                                        inputRange: [0, 1],
                                        outputRange: [0.5, 1]
                                    })
                                }
                            ]
                        }}>
                            <Image source={{uri: lastPhotoUri}} style={styles.thumbnail}/>
                        </Animated.View>
                    ) : (
                        <View style={styles.thumbnailPlaceholder}/>
                    )}
                </TouchableOpacity>

                <TouchableOpacity
                    style={[styles.captureButton, isCapturing && styles.captureButtonDisabled]}
                    onPress={takePicture}
                    disabled={isCapturing}
                >
                    <View style={styles.captureButtonInner}/>
                </TouchableOpacity>

                <View style={styles.sidePlaceholder}/>
            </View>
        </View>
    );
}

const styles = StyleSheet.create({
    container: {
        flex: 1,
        backgroundColor: '#000',
        justifyContent: 'center',
        alignItems: 'center',
    },
    camera: {
        flex: 1,
        width: '100%',
    },
    cameraContainer: {
        flex: 1,
        width: '100%',
    },
    text: {
        fontSize: 18,
        color: '#fff',
        textAlign: 'center',
        marginBottom: 10,
    },
    subText: {
        fontSize: 14,
        color: '#999',
        textAlign: 'center',
    },
    statusContainer: {
        position: 'absolute',
        top: 60,
        alignSelf: 'center',
        backgroundColor: 'rgba(0, 0, 0, 0.6)',
        paddingHorizontal: 16,
        paddingVertical: 8,
        borderRadius: 20,
    },
    statusText: {
        color: '#fff',
        fontSize: 16,
        fontWeight: '600',
    },
    controlsContainer: {
        position: 'absolute',
        bottom: 40,
        width: '100%',
        flexDirection: 'row',
        justifyContent: 'space-around',
        alignItems: 'center',
        paddingHorizontal: 20,
    },
    thumbnailContainer: {
        width: 60,
        height: 60,
        borderRadius: 10,
        overflow: 'hidden',
        backgroundColor: 'rgba(255, 255, 255, 0.1)',
        justifyContent: 'center',
        alignItems: 'center',
    },
    thumbnail: {
        width: 60,
        height: 60,
        borderRadius: 10,
    },
    thumbnailPlaceholder: {
        width: 40,
        height: 40,
        borderRadius: 5,
        backgroundColor: 'rgba(255, 255, 255, 0.2)',
    },
    sidePlaceholder: {
        width: 60,
    },
    captureAnimationOverlay: {
        position: 'absolute',
        top: '10%',
        left: '10%',
        width: '80%',
        height: '60%',
        justifyContent: 'center',
        alignItems: 'center',
        zIndex: 10,
    },
    fullImage: {
        width: '100%',
        height: '100%',
        borderRadius: 20,
    },
    faceCircle: {
        position: 'absolute',
        borderWidth: 2,
        borderColor: '#00ff00',
        borderRadius: 10, // Changed from 1000 to 10 for better debug visibility
        backgroundColor: 'rgba(0, 255, 0, 0.2)',
    },
    focusRing: {
        position: 'absolute',
        width: 80,
        height: 80,
        borderWidth: 2,
        borderColor: '#fff',
        borderRadius: 40,
        backgroundColor: 'rgba(255, 255, 255, 0.1)',
    },
    captureButton: {
        width: 70,
        height: 70,
        borderRadius: 35,
        backgroundColor: 'rgba(255, 255, 255, 0.3)',
        justifyContent: 'center',
        alignItems: 'center',
        borderWidth: 4,
        borderColor: '#fff',
    },
    captureButtonDisabled: {
        opacity: 0.5,
    },
    captureButtonInner: {
        width: 60,
        height: 60,
        borderRadius: 30,
        backgroundColor: '#fff',
    },
    button: {
        backgroundColor: '#007AFF',
        paddingHorizontal: 20,
        paddingVertical: 10,
        borderRadius: 8,
        marginTop: 10,
    },
    buttonText: {
        color: '#fff',
        fontSize: 16,
        fontWeight: '600',
    },
    faceBox: {
        position: 'absolute',
        borderWidth: 3,
        borderColor: '#00ff00',
        borderRadius: 8,
        backgroundColor: 'rgba(0, 255, 0, 0.1)',
    },
});

