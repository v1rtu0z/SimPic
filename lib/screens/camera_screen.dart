import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart' as path;
import 'package:url_launcher/url_launcher.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:open_file/open_file.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_selfie_segmentation/google_mlkit_selfie_segmentation.dart';
import 'package:native_device_orientation/native_device_orientation.dart';
import 'package:image/image.dart' as img;
import 'dart:typed_data';
import '../models/distance_coaching_scenario.dart';
import '../widgets/coaching_overlay.dart';
import '../models/composition_guidance.dart';
import '../widgets/composition_grid_overlay.dart';
import '../models/orientation_guidance.dart';
import '../models/exposure_guidance.dart';
import '../models/blink_detection.dart';
import '../models/framing_score.dart';
import '../models/app_settings.dart';
import '../models/portrait_analysis.dart';
import '../widgets/portrait_indicator.dart';
import 'settings_screen.dart';

class CameraScreen extends StatefulWidget {
  CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  CameraDescription? _currentCamera;
  bool _isInitialized = false;
  bool _hasPermission = false;
  bool _isCapturing = false;
  bool _isAiAdviceLoading = false;
  File? _lastImageFile;
  String? _lastImagePath;
  String? _lastImageUri; // Content URI for opening in gallery
  GlobalKey _previewButtonKey = GlobalKey();
  final GlobalKey _previewKey = GlobalKey();
  
  // Animation for flash effect
  late AnimationController _flashAnimationController;
  late Animation<double> _flashAnimation;
  
  // Animation for photo minimizing into preview
  late AnimationController _minimizeAnimationController;
  late Animation<double> _minimizeAnimation;
  File? _minimizingImage;
  Rect? _previewButtonRect;
  
  // Face detection
  FaceDetector? _faceDetector;
  SelfieSegmenter? _selfieSegmenter;
  List<Face> _detectedFaces = [];
  bool _isProcessing = false;
  int _frameCounter = 0;
  Size? _imageSize;
  int _detectedFacesRotation = 0;
  NativeDeviceOrientation _detectedFacesOrientation = NativeDeviceOrientation.portraitUp;
  
  // Orientation tracking
  NativeDeviceOrientation _deviceOrientation = NativeDeviceOrientation.portraitUp;
  NativeDeviceOrientation _stableLayoutOrientation = NativeDeviceOrientation.portraitUp;
  StreamSubscription<NativeDeviceOrientation>? _orientationSubscription;
  
  // Distance coaching
  DistanceCoachingResult? _distanceCoachingResult;
  DistanceCoachingScenario? _currentDistanceScenario;
  int _significantFaceCount = 0;
  
  // Composition guidance
  CompositionGuidanceResult? _compositionGuidanceResult;
  PowerPoint? _previousPowerPoint; // For hysteresis to prevent flickering
  Offset? _lastDisplayFaceCenter; // Tracked for UI overlay
  Size? _lastDisplayImageSize;    // Tracked for UI overlay
  
  // Exposure analysis
  FaceExposureResult? _faceExposureResult;
  
  // Blink detection
  BlinkDetectionResult? _blinkDetectionResult;
  
  // Framing score
  FramingScoreResult? _framingScoreResult;
  
  // Portrait detection
  PortraitAnalysisResult? _portraitAnalysisResult;
  PortraitDetectionState _portraitDetectionState = PortraitDetectionState();
  bool _isHardwareExtensionAvailable = false; // TODO: Check CameraX extensions
  
  // Focus feedback
  Offset? _focusPoint;
  AnimationController? _focusAnimationController;
  Animation<double>? _focusAnimation;
  Timer? _focusTimer;
  
  // Face tracking for stability in distance coaching (used in _selectBestFace)
  Rect? _lastTrackedFaceBounds;
  
  // Auto-exposure/focus lock
  Face? _lockedFace;
  DateTime? _lastLockTime;
  static const Duration _lockThreshold = Duration(milliseconds: 500);

  // Flashlight hysteresis
  int _flashConsistencyCounter = 0;
  static const int _flashConsistencyThreshold = 10;

  // Coaching consistency counters
  int _distanceConsistencyCounter = 0;
  DistanceCoachingStatus? _lastStableDistanceStatus;
  
  int _compositionConsistencyCounter = 0;
  CompositionStatus? _lastStableCompositionStatus;
  
  int _exposureConsistencyCounter = 0;
  ExposureStatus? _lastStableExposureStatus;
  
  int _blinkConsistencyCounter = 0;
  bool? _lastStableBlinkStatus;

  int _faceCountConsistencyCounter = 0;
  int? _lastStableFaceCountRaw;

  static const int _coachingConsistencyThreshold = 10;
  static const int _blinkConsistencyThreshold = 20;
  static const int _faceCountConsistencyThreshold = 5; // Half of coaching threshold for faster face count/orientation updates

  // Frame comparison for stability (skip face detection when camera is stationary)
  Uint8List? _previousFrameSample;
  Size? _previousImageSize;

  // Auto-shutter
  DateTime? _lastAutoCaptureTime;
  int _goodFrameCount = 0;
  static const int _autoShutterRequiredGoodFrames = 5; // Reduced from 10 for faster response
  static const Duration _autoShutterCooldown = Duration(seconds: 3);

  // Shutter button pulse animation
  late AnimationController _shutterPulseController;
  late Animation<double> _shutterPulseAnimation;

  final model =
      FirebaseAI.googleAI().generativeModel(model: 'gemini-2.5-flash-lite');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    appSettings.addListener(_onSettingsChanged);
    appSettings.addListener(_updateFlashMode);
    
    // Listen to physical device orientation changes using sensors
    _orientationSubscription = NativeDeviceOrientationCommunicator()
        .onOrientationChanged(useSensor: true)
        .listen((orientation) {
      if (mounted) {
        // Ignore unknown orientation to prevent flickering
        if (orientation == NativeDeviceOrientation.unknown) return;

        setState(() {
          _deviceOrientation = orientation;
          // Stabilize layout orientation to prevent the control bar from jumping
          _updateLayoutOrientation(orientation);
        });
      }
    });
    
    // Initialize flash animation
    _flashAnimationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _flashAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _flashAnimationController,
        curve: Curves.easeOut,
      ),
    );
    
    // Initialize minimize animation
    _minimizeAnimationController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _minimizeAnimation = CurvedAnimation(
      parent: _minimizeAnimationController,
      curve: Curves.easeInOut,
    );
    
    // Initialize face detector
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: true,
        enableLandmarks: false,
        enableTracking: false,
        performanceMode: FaceDetectorMode.accurate,
      ),
    );
    
    // Initialize selfie segmenter for bokeh effects
    _selfieSegmenter = SelfieSegmenter(
      mode: SegmenterMode.stream,
      enableRawSizeMask: false, // We'll use the processed mask
    );
    
    // Initialize focus animation
    _focusAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _focusAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _focusAnimationController!,
        curve: Curves.easeOut,
      ),
    );

    // Initialize shutter pulse animation
    _shutterPulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _shutterPulseAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _shutterPulseController,
        curve: Curves.easeInOut,
      ),
    );
    
    _initializeCamera();
    _loadLatestPhoto();
  }

  @override
  void dispose() {
    appSettings.removeListener(_onSettingsChanged);
    appSettings.removeListener(_updateFlashMode);
    WidgetsBinding.instance.removeObserver(this);
    _orientationSubscription?.cancel();
    _controller?.dispose();
    _flashAnimationController.dispose();
    _minimizeAnimationController.dispose();
    _focusAnimationController?.dispose();
    _shutterPulseController.dispose();
    _focusTimer?.cancel();
    _faceDetector?.close();
    _selfieSegmenter?.close();
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) {
      setState(() {
        if (!appSettings.faceDetectionEnabled) {
          _detectedFaces = [];
          _distanceCoachingResult = null;
          _compositionGuidanceResult = null;
          _significantFaceCount = 0;
          _portraitAnalysisResult = null;
          _portraitDetectionState.reset();
          _blinkDetectionResult = null;
          _blinkConsistencyCounter = 0;
          _lastStableBlinkStatus = null;
        } else {
          if (!appSettings.distanceCoachingEnabled) {
            _distanceCoachingResult = null;
          }
          if (!appSettings.compositionGridEnabled) {
            _compositionGuidanceResult = null;
          }
          if (!appSettings.autoPortraitEnabled) {
            _portraitAnalysisResult = null;
            _portraitDetectionState.reset();
          }
          if (!appSettings.eyesClosedDetectionEnabled) {
            _blinkDetectionResult = null;
            _blinkConsistencyCounter = 0;
            _lastStableBlinkStatus = null;
          }
        }
      });
    }
  }

  void _updateFlashMode() {
    if (_controller == null || !_controller!.value.isInitialized) return;
    
    FlashMode cameraFlashMode;
    switch (appSettings.flashMode) {
      case FlashModeSetting.off:
        cameraFlashMode = FlashMode.off;
        break;
      case FlashModeSetting.on:
        // Use capture flash so it triggers at shutter time.
        cameraFlashMode = FlashMode.always;
        break;
      case FlashModeSetting.auto:
        // We handle this dynamically in _processCameraImage
        // But we set it to off initially to avoid confusion
        cameraFlashMode = FlashMode.off;
        break;
    }
    
    _controller!.setFlashMode(cameraFlashMode).catchError((e) {
      debugPrint('Error setting flash mode: $e');
    });
  }

  /// Updates the layout orientation for UI elements (icons, text)
  void _updateLayoutOrientation(NativeDeviceOrientation newOrientation) {
    _stableLayoutOrientation = newOrientation;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Refresh latest photo when app becomes active
    if (state == AppLifecycleState.resumed) {
      _loadLatestPhoto();
    }
    // Camera controller handles lifecycle automatically
  }


  Future<void> _initializeCamera() async {
    // Request camera permission
    final cameraStatus = await Permission.camera.request();
    if (cameraStatus.isDenied || cameraStatus.isPermanentlyDenied) {
      setState(() {
        _hasPermission = false;
      });
      return;
    }

    setState(() {
      _hasPermission = true;
    });

    // Get available cameras
    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        return;
      }

      // Use back camera by default
      _currentCamera = _cameras!.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras!.first,
      );

      // Update app settings with lens direction
      appSettings.setCameraLens(_currentCamera!.lensDirection == CameraLensDirection.front);

      // Initialize camera controller with platform-appropriate format for ML Kit compatibility
      // Android uses NV21, iOS uses YUV420
      _controller = CameraController(
        _currentCamera!,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid 
            ? ImageFormatGroup.nv21 
            : ImageFormatGroup.yuv420,
      );

      await _controller!.initialize();
      
      // Set initial flash mode from settings
      _updateFlashMode();
      
      // Enable continuous autofocus
      await _controller!.setFocusMode(FocusMode.auto);
      
      // Debug: Print sensor orientation clearly
      debugPrint('=============================================');
      debugPrint('CAMERA SENSOR ORIENTATION: ${_currentCamera!.sensorOrientation}°');
      debugPrint('=============================================');

      // Start image stream for face detection
      _controller!.startImageStream(_processCameraImage);

      setState(() {
        _isInitialized = true;
      });
    } catch (e) {
      debugPrint('Error initializing camera: $e');
    }
  }

  Future<void> _loadLatestPhoto() async {
    try {
      // Do not trigger a system prompt at app start.
      // We only read gallery if permission was already granted.
      final PermissionState permission = await PhotoManager.getPermissionState(
        requestOption: const PermissionRequestOption(
          androidPermission: AndroidPermission(
            type: RequestType.image,
            mediaLocation: false,
          ),
        ),
      );
      debugPrint('[_loadLatestPhoto] Permission state: $permission');
      
      if (!permission.hasAccess) {
        debugPrint('[_loadLatestPhoto] No photo access granted');
        return;
      }
      
      // Configure filter to sort by creation date descending (newest first)
      final filterOptions = FilterOptionGroup(
        orders: [
          const OrderOption(
            type: OrderOptionType.createDate,
            asc: false, // false = descending order (newest first)
          ),
        ],
      );
      
      // Get only the Camera album (DCIM on Android) with sorting applied
      final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        hasAll: false, // Don't include "All photos" album
        filterOption: filterOptions,
      );
      debugPrint('[_loadLatestPhoto] Found ${albums.length} albums: ${albums.map((a) => a.name).join(", ")}');
      
      if (albums.isEmpty) {
        debugPrint('[_loadLatestPhoto] No albums found');
        return;
      }
      
      // Look for Camera-related albums
      // On Android: Anything containing "DCIM" (includes Camera subdirectory and other DCIM folders)
      // On iOS: "Camera Roll" or "Recents"
      List<AssetPathEntity> cameraAlbums = [];
      
      for (final album in albums) {
        final name = album.name.toLowerCase();
        debugPrint('[_loadLatestPhoto] Checking album: ${album.name}');
        
        if (Platform.isAndroid) {
          // Android: Look for anything with DCIM in the name
          // This includes "DCIM", "Camera" (under DCIM), and any other DCIM subdirectories
          if (name.contains('dcim') || name == 'camera') {
            cameraAlbums.add(album);
            debugPrint('[_loadLatestPhoto] Found DCIM-related album: ${album.name}');
          }
        } else if (Platform.isIOS) {
          // iOS: Look for "Camera Roll" or "Recents"
          if (name.contains('camera') || name.contains('recents')) {
            cameraAlbums.add(album);
            debugPrint('[_loadLatestPhoto] Found Camera album: ${album.name}');
          }
        }
      }
      
      if (cameraAlbums.isEmpty) {
        debugPrint('[_loadLatestPhoto] No Camera/DCIM albums found');
        return;
      }
      
      // If we found multiple DCIM albums, we need to check all of them and find the newest photo
      AssetEntity? newestAsset;
      DateTime? newestDate;
      
      for (final album in cameraAlbums) {
        final int count = await album.assetCountAsync;
        debugPrint('[_loadLatestPhoto] Album "${album.name}" has $count photos');
        
        if (count == 0) continue;
        
        // Get the first photo from this album (should be newest due to our sort order)
        final List<AssetEntity> media = await album.getAssetListRange(
          start: 0,
          end: 1,
        );
        
        if (media.isNotEmpty) {
          final asset = media.first;
          final date = asset.createDateTime;
          debugPrint('[_loadLatestPhoto] Album "${album.name}" latest: ${asset.id}, created: $date');
          
          if (newestDate == null || date.isAfter(newestDate)) {
            newestAsset = asset;
            newestDate = date;
          }
        }
      }
      
      if (newestAsset == null) {
        debugPrint('[_loadLatestPhoto] No photos found in DCIM albums');
        return;
      }
      
      debugPrint('[_loadLatestPhoto] Selected newest photo ID: ${newestAsset.id}, created: $newestDate');
      
      // Get the file for preview
      final File? file = await newestAsset.file;
      
      if (file != null && mounted) {
        setState(() {
          _lastImageFile = file;
          _lastImagePath = file.path;
          _lastImageUri = newestAsset!.id; // We already checked newestAsset is not null above
        });
        debugPrint('[_loadLatestPhoto] Loaded latest photo from DCIM: ${file.path}');
      }
    } catch (e) {
      debugPrint('[_loadLatestPhoto] Error loading latest photo: $e');
    }
  }

  /// After capture, checks the JPEG on disk. Returns true if any face is found or checks are skipped.
  Future<bool> _capturedFileContainsFace(String filePath) async {
    if (_faceDetector == null || !appSettings.faceDetectionEnabled) {
      return true;
    }
    try {
      final inputImage = InputImage.fromFilePath(filePath);
      final faces = await _faceDetector!.processImage(inputImage);
      return faces.isNotEmpty;
    } catch (e) {
      debugPrint('[_capturedFileContainsFace] $e');
      return true;
    }
  }

  void _showNoPersonInPhotoDialog() {
    final mq = MediaQuery.of(context);
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black45,
      builder: (dialogContext) {
        return Dialog(
          alignment: Alignment.topCenter,
          insetPadding: EdgeInsets.fromLTRB(
            20,
            mq.padding.top + 52,
            20,
            mq.size.height * 0.38,
          ),
          backgroundColor: const Color(0xFF2A2A2A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.person_off_outlined, color: Colors.amber.shade200, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'No person detected',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  'This shot does not appear to include anyone. Your photo was still saved.',
                  style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.35),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('OK'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _takePicture() async {
    if (_controller == null || !_controller!.value.isInitialized || _isCapturing) {
      return;
    }

    // Blink detection: wait up to 500ms for eyes to open
    if (appSettings.eyesClosedDetectionEnabled &&
        _blinkDetectionResult != null &&
        _blinkDetectionResult!.eitherEyeClosed) {
      debugPrint('[_takePicture] Eyes closed detected, waiting up to 500ms...');
      final startTime = DateTime.now();
      while (DateTime.now().difference(startTime).inMilliseconds < 500) {
        await Future.delayed(const Duration(milliseconds: 50));
        if (_blinkDetectionResult == null || _blinkDetectionResult!.canShoot) {
          debugPrint('[_takePicture] Eyes opened! Proceeding with capture.');
          break;
        }
      }
      if (_blinkDetectionResult != null && _blinkDetectionResult!.eitherEyeClosed) {
        debugPrint('[_takePicture] Eyes still closed after 500ms, capturing anyway.');
      }
    }

    setState(() {
      _isCapturing = true;
    });

    String? pathForFaceCheck;
    try {
      // Ensure flash mode is correct right before capture.
      if (_controller != null && _controller!.value.isInitialized) {
        FlashMode captureFlashMode = FlashMode.off;
        switch (appSettings.flashMode) {
          case FlashModeSetting.off:
            captureFlashMode = FlashMode.off;
            break;
          case FlashModeSetting.on:
            captureFlashMode = FlashMode.always;
            break;
          case FlashModeSetting.auto:
            final exposure = _faceExposureResult?.status;
            final needsFlash = exposure == ExposureStatus.underexposed ||
                exposure == ExposureStatus.shadowed;
            captureFlashMode = needsFlash ? FlashMode.always : FlashMode.off;
            break;
        }
        await _controller!.setFlashMode(captureFlashMode);
      }

      // Stop image stream before taking photo
      if (_controller!.value.isStreamingImages) {
        await _controller!.stopImageStream();
      }

      // Trigger flash animation
      _flashAnimationController.forward().then((_) {
        _flashAnimationController.reverse();
      });

      // Take the picture
      final XFile image = await _controller!.takePicture();
      
      // Apply bokeh effect if portrait mode is active
      Uint8List finalImageBytes;
      if (appSettings.autoPortraitEnabled && 
          _portraitAnalysisResult != null && 
          _portraitAnalysisResult!.isActive) {
        debugPrint('[_takePicture] Portrait mode active, applying bokeh effect...');
        try {
          finalImageBytes = await _applyBokehEffect(image.path);
          debugPrint('[_takePicture] Bokeh effect applied successfully');
        } catch (e) {
          debugPrint('[_takePicture] Error applying bokeh, using original image: $e');
          finalImageBytes = await File(image.path).readAsBytes();
        }
      } else {
        finalImageBytes = await File(image.path).readAsBytes();
      }

      // Save to gallery and get the asset ID directly
      // This matches React Native's MediaLibrary.createAssetAsync() behavior
      String? savedImageUri;
      File? savedImageFile;
      try {
        debugPrint('[_takePicture] Saving image to gallery...');
        
        // Use photo_manager to save and get the asset ID directly
        // This is more reliable than gallery_saver_plus + querying
        // Ask for photo permission only when user actually takes a picture.
        final PermissionState permission = await PhotoManager.requestPermissionExtend();
        if (!permission.hasAccess) {
          throw Exception('Photo permission not granted');
        }
        
        // Save using photo_manager editor - returns AssetEntity with ID directly
        // (finalImageBytes already processed with bokeh if portrait mode was active)
        // On Android: Save to DCIM/Camera directory (standard camera photos location)
        // On iOS: relativePath is ignored, photos are saved to Camera Roll automatically
        final AssetEntity? savedAsset = Platform.isAndroid
            ? await PhotoManager.editor.saveImage(
                finalImageBytes,
                filename: path.basename(image.path),
                relativePath: 'DCIM/Camera',
              )
            : await PhotoManager.editor.saveImage(
                finalImageBytes,
                filename: path.basename(image.path),
              );
        
        if (savedAsset == null) {
          throw Exception('Failed to save image to gallery');
        }
        
        // Get the asset ID (MediaStore ID on Android)
        savedImageUri = savedAsset.id;
        debugPrint('[_takePicture] Saved image with MediaStore ID: $savedImageUri');
        
        // Get the file for preview
        savedImageFile = await savedAsset.file;
        if (savedImageFile != null) {
          debugPrint('[_takePicture] Saved image file: ${savedImageFile.path}');
        }
        
        // Get preview button position for animation
        final RenderBox? previewBox = _previewButtonKey.currentContext?.findRenderObject() as RenderBox?;
        if (previewBox != null && previewBox.attached) {
          final position = previewBox.localToGlobal(Offset.zero);
          final size = previewBox.size;
          _previewButtonRect = Rect.fromLTWH(
            position.dx,
            position.dy,
            size.width,
            size.height,
          );
        }
        
        // Use the saved file for preview (or fallback to temp file)
        final previewFile = savedImageFile ?? File(image.path);
        
        // Start minimize animation
        setState(() {
          _minimizingImage = previewFile;
          _minimizeAnimationController.reset();
        });
        await _minimizeAnimationController.forward();
        
        setState(() {
          _lastImagePath = previewFile.path;
          _lastImageFile = previewFile;
          _lastImageUri = savedImageUri; // This is the MediaStore ID for opening in gallery
          _minimizingImage = null;
        });
        pathForFaceCheck = previewFile.path;

        debugPrint('Photo saved to gallery successfully');
      } catch (e) {
        debugPrint('Error saving to gallery: $e');
        // If saving fails, still use the original temp file
        setState(() {
          _lastImagePath = image.path;
          _lastImageFile = File(image.path);
        });
        pathForFaceCheck = image.path;
        debugPrint('Using temp file: ${image.path}');
      }
    } catch (e) {
      debugPrint('Error taking picture: $e');
    } finally {
      // Restart image stream after taking photo
      if (_controller != null && 
          _controller!.value.isInitialized && 
          !_controller!.value.isStreamingImages) {
        try {
          await _controller!.startImageStream(_processCameraImage);
        } catch (e) {
          debugPrint('Error restarting image stream: $e');
        }
      }

      // Restore preview flash behavior after capture.
      _updateFlashMode();
      
      setState(() {
        _isCapturing = false;
      });
    }

    if (mounted &&
        pathForFaceCheck != null &&
        appSettings.faceDetectionEnabled &&
        _faceDetector != null) {
      final hasFace = await _capturedFileContainsFace(pathForFaceCheck);
      if (mounted && !hasFace) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _showNoPersonInPhotoDialog();
          }
        });
      }
    }
  }

  Future<void> _processCameraImage(CameraImage image) async {
    // Skip frames for optimization (process every 2nd frame for more real-time feel)
    _frameCounter++;
    FaceDetectorPainter._frameCounter++;

    // Capture current orientation data to ensure consistency throughout processing
    final currentOrientation = _deviceOrientation;

    // Skip if already processing to prevent queue buildup
    if (_isProcessing || _faceDetector == null || !appSettings.faceDetectionEnabled) {
      if (!appSettings.faceDetectionEnabled && _detectedFaces.isNotEmpty) {
        setState(() {
          _detectedFaces = [];
          _distanceCoachingResult = null;
          _compositionGuidanceResult = null;
        });
      }
      return;
    }

    _isProcessing = true;

    try {
      final imageSize = Size(image.width.toDouble(), image.height.toDouble());
      
      // Run face detection on every frame (no throttling)
      final currentRotation = _calculateRotationDegrees();
      final inputImage = _convertCameraImage(image, currentRotation);
      if (inputImage == null) {
        _isProcessing = false;
        return;
      }
      
      final List<Face> faces = await _faceDetector!.processImage(inputImage);
      
      // Store frame sample for potential future optimization
      _previousFrameSample = _sampleFrame(image);
      _previousImageSize = imageSize;
        
        int significantFaceCount = 0;
        DistanceCoachingResult? coachingResult;
        CompositionGuidanceResult? compositionResult;
        FaceExposureResult? exposureResult;
        BlinkDetectionResult? blinkResult;
        FramingScoreResult? framingScore;
        Offset? displayFaceCenter;
        Size? displayImageSize;

        // Process face detection results
        if (faces.isNotEmpty && imageSize.height > 0) {
          // Determine display height and effective size based on rotation
          final double displayHeight;
          final Size effectiveSize;
          if (currentRotation == 90 || currentRotation == 270) {
            displayHeight = imageSize.width; // camW is height in portrait
            effectiveSize = Size(imageSize.height, imageSize.width); // camH x camW (e.g. 720x1280)
          } else {
            displayHeight = imageSize.height; // camH is height in landscape
            effectiveSize = Size(imageSize.width, imageSize.height); // camW x camH (e.g. 1280x720)
          }

          // Count significant faces for orientation suggestion
          // Use a threshold that accounts for full-body shots (where faces are smaller, ~8-12%)
          final minDimension = min(imageSize.width, imageSize.height);
          // 7% threshold is enough to catch full-body subjects while ignoring small background faces
          final significantPixelThreshold = minDimension * 0.07;

          for (final face in faces) {
            // With correct rotation, ML Kit height is always the vertical axis relative to display
            if (face.boundingBox.height >= significantPixelThreshold) {
              significantFaceCount++;
            }
          }

          // Select best face for coaching and focus (handles multiple faces)
          Face? bestFace = _selectBestFace(faces, effectiveSize);
          
          if (bestFace != null) {
            final faceHeight = bestFace.boundingBox.height;
            
            // Safety check: ensure valid face height
            if (faceHeight > 0 && displayHeight > 0) {
              final faceHeightPercentage = (faceHeight / displayHeight) * 100.0;
              
              // Evaluate distance coaching with hysteresis to prevent flickering
              coachingResult = evaluateDistanceCoaching(
                faceHeightPercentage,
                _currentDistanceScenario,
                significantFaceCount: significantFaceCount,
              );
              
              // Camera image size (usually landscape: e.g. 1280x720)
              final camW = imageSize.width;
              final camH = imageSize.height;

              // Calculate face center in camera coordinates (as returned by ML Kit)
              final rawFaceCenterX = bestFace.boundingBox.left + (bestFace.boundingBox.width / 2);
              final rawFaceCenterY = bestFace.boundingBox.top + (bestFace.boundingBox.height / 2);

              if (currentRotation == 90 || currentRotation == 270) {
                displayImageSize = Size(camH, camW);
              } else {
                displayImageSize = Size(camW, camH);
              }

              // Transform raw coordinates to display-aligned coordinates based on rotation
              // This logic must match _scaleRect's rotation mapping to ensure UI consistency
              final double nx = rawFaceCenterX / displayImageSize.width;
              final double ny = rawFaceCenterY / displayImageSize.height;
              
              double finalNx, finalNy;
              int degrees = 0;
              switch (currentOrientation) {
                case NativeDeviceOrientation.landscapeRight:
                  degrees = 90;
                  break;
                case NativeDeviceOrientation.portraitDown:
                  degrees = 180;
                  break;
                case NativeDeviceOrientation.landscapeLeft:
                  degrees = 270;
                  break;
                default:
                  degrees = 0;
              }

              if (degrees == 90) {
                finalNx = ny;
                finalNy = 1.0 - nx;
              } else if (degrees == 180) {
                finalNx = 1.0 - nx;
                finalNy = 1.0 - ny;
              } else if (degrees == 270) {
                finalNx = 1.0 - ny;
                finalNy = nx;
              } else {
                finalNx = nx;
                finalNy = ny;
              }

              // Handle mirroring for front camera (must match _scaleRect)
              if (_currentCamera?.lensDirection == CameraLensDirection.front) {
                if (currentOrientation == NativeDeviceOrientation.landscapeLeft || 
                    currentOrientation == NativeDeviceOrientation.landscapeRight) {
                  finalNy = 1.0 - finalNy;
                } else {
                  finalNx = 1.0 - finalNx;
                }
              }

              displayFaceCenter = Offset(
                finalNx * displayImageSize.width, 
                finalNy * displayImageSize.height
              );
              
              if (_frameCounter % 30 == 0) {
                debugPrint('CALCULATED_FACE_CENTER: $displayFaceCenter on display size $displayImageSize');
              }
              
              // Now evaluate composition with display coordinates
              compositionResult = evaluateComposition(
                displayFaceCenter,
                displayImageSize,
                previousPowerPoint: _previousPowerPoint,
              );

              // Perform Lighting Intelligence (Exposure Analysis)
              if (appSettings.lightingIntelligenceEnabled) {
                exposureResult = analyzeFaceExposure(
                  image,
                  bestFace.boundingBox,
                  currentRotation,
                  _currentCamera?.lensDirection == CameraLensDirection.front,
                );
              }

              // Perform Blink Detection
              if (appSettings.eyesClosedDetectionEnabled) {
                blinkResult = evaluateBlink(
                  bestFace.leftEyeOpenProbability,
                  bestFace.rightEyeOpenProbability,
                );
              }

              // Perform Auto-exposure Lock on Face
              if (appSettings.autoExposureLockEnabled) {
                _handleFaceExposureLock(bestFace, currentRotation, imageSize);
              } else {
                _lockedFace = null;
              }

              // Perform Portrait Analysis (if enabled)
              // Only analyze if we have exactly 1 significant face (portrait mode requirement)
              if (appSettings.autoPortraitEnabled && significantFaceCount == 1 && displayImageSize != null) {
                // Filter to only significant faces for portrait analysis
                final significantFaces = faces.where((face) {
                  final faceHeight = face.boundingBox.height;
                  final minDimension = min(imageSize.width, imageSize.height);
                  final significantPixelThreshold = minDimension * 0.07;
                  return faceHeight >= significantPixelThreshold;
                }).toList();
                
                _portraitAnalysisResult = analyzePortraitCandidate(
                  faces: significantFaces,
                  imageSize: imageSize,
                  displayImageSize: displayImageSize,
                  faceCenter: displayFaceCenter,
                  state: _portraitDetectionState,
                  isHardwareExtensionAvailable: _isHardwareExtensionAvailable,
                  frameCounter: _frameCounter,
                  isFrontCamera: _currentCamera?.lensDirection == CameraLensDirection.front,
                  isWellComposed: compositionResult?.status == CompositionStatus.wellPositioned,
                );
              } else {
                if (appSettings.autoPortraitEnabled && significantFaceCount != 1) {
                  // Reset if not exactly 1 face
                  _portraitDetectionState.reset();
                }
                _portraitAnalysisResult = null;
              }
            } // Close if (faceHeight > 0 && displayHeight > 0)
          } else {
            // No face detected or no best face, clear locked face
            _lockedFace = null;
            // Reset portrait detection when no face
            if (appSettings.autoPortraitEnabled) {
              _portraitDetectionState.reset();
              _portraitAnalysisResult = null;
            }
          }
        } else {
          // No faces detected - reset portrait detection
          if (appSettings.autoPortraitEnabled) {
            _portraitDetectionState.reset();
            _portraitAnalysisResult = null;
          }
        }

        // Always update UI when face detection runs, combining all updates into one setState
        if (mounted) {
          setState(() {
            _detectedFaces = faces;
            _imageSize = imageSize;
            _detectedFacesRotation = currentRotation;
            _detectedFacesOrientation = currentOrientation;
            
            // --- Stability Logic for Coaching Guides ---
            // Most guides require 10 frames of consistent conditions to update UI
            // Face count uses 5 frames for faster orientation overlay updates
            
            // 0. Significant Face Count Stability (affects Orientation Suggestion)
            if (significantFaceCount == _lastStableFaceCountRaw) {
              _faceCountConsistencyCounter++;
            } else {
              _faceCountConsistencyCounter = 1;
              _lastStableFaceCountRaw = significantFaceCount;
            }
            if (_faceCountConsistencyCounter >= _faceCountConsistencyThreshold) {
              _significantFaceCount = significantFaceCount;
            }

            // 1. Distance Coaching Stability
            if (coachingResult != null) {
              if (coachingResult.status == _lastStableDistanceStatus) {
                _distanceConsistencyCounter++;
              } else {
                _distanceConsistencyCounter = 1;
                _lastStableDistanceStatus = coachingResult.status;
              }
              if (_distanceConsistencyCounter >= _coachingConsistencyThreshold) {
                _distanceCoachingResult = appSettings.distanceCoachingEnabled ? coachingResult : null;
                _currentDistanceScenario = coachingResult.scenario;
              }
            } else {
              _distanceConsistencyCounter = 0;
              _lastStableDistanceStatus = null;
              _distanceCoachingResult = null;
              _currentDistanceScenario = null;
            }

            // 2. Composition Guidance Stability
            if (compositionResult != null) {
              if (compositionResult.status == _lastStableCompositionStatus) {
                _compositionConsistencyCounter++;
              } else {
                _compositionConsistencyCounter = 1;
                _lastStableCompositionStatus = compositionResult.status;
              }
              if (_compositionConsistencyCounter >= _coachingConsistencyThreshold) {
                _compositionGuidanceResult = appSettings.compositionGridEnabled ? compositionResult : null;
                _previousPowerPoint = compositionResult.nearestPowerPoint;
              }
            } else {
              _compositionConsistencyCounter = 0;
              _lastStableCompositionStatus = null;
              _compositionGuidanceResult = null;
            }

            // 3. Exposure Analysis Stability
            if (exposureResult != null) {
              if (exposureResult.status == _lastStableExposureStatus) {
                _exposureConsistencyCounter++;
              } else {
                _exposureConsistencyCounter = 1;
                _lastStableExposureStatus = exposureResult.status;
              }
              if (_exposureConsistencyCounter >= _coachingConsistencyThreshold) {
                _faceExposureResult = appSettings.lightingIntelligenceEnabled ? exposureResult : null;
              }
            } else {
              _exposureConsistencyCounter = 0;
              _lastStableExposureStatus = null;
              _faceExposureResult = null;
            }

            // 4. Blink Detection Stability
            if (appSettings.eyesClosedDetectionEnabled && blinkResult != null) {
              final isBlinking = blinkResult.eitherEyeClosed;
              if (isBlinking == _lastStableBlinkStatus) {
                _blinkConsistencyCounter++;
              } else {
                _blinkConsistencyCounter = 1;
                _lastStableBlinkStatus = isBlinking;
              }
              if (_blinkConsistencyCounter >= _blinkConsistencyThreshold) {
                _blinkDetectionResult = blinkResult;
              }
            } else {
              _blinkConsistencyCounter = 0;
              _lastStableBlinkStatus = null;
              _blinkDetectionResult = null;
            }

            // Update Framing Score using STABILIZED results for UI consistency
            _framingScoreResult = calculateFramingScore(
              distanceResult: _distanceCoachingResult,
              compositionResult: _compositionGuidanceResult,
              exposureResult: _faceExposureResult,
              blinkResult: appSettings.eyesClosedDetectionEnabled
                  ? _blinkDetectionResult
                  : null,
            );

            // Handle Flashlight Auto-toggle based on light detection
            if (appSettings.flashMode == FlashModeSetting.auto && exposureResult != null) {
              final needsFlash = exposureResult.status == ExposureStatus.underexposed || 
                                exposureResult.status == ExposureStatus.shadowed;
              
              // Frame-based hysteresis to prevent flickering
              if (needsFlash) {
                // If we need flash, increment counter (capped at threshold)
                if (_flashConsistencyCounter < 0) _flashConsistencyCounter = 0; // Reset if it was negative
                _flashConsistencyCounter++;
              } else {
                // If we don't need flash, decrement counter (or use separate counter, 
                // but a single signed counter works well for toggling)
                if (_flashConsistencyCounter > 0) _flashConsistencyCounter = 0; // Reset if it was positive
                _flashConsistencyCounter--;
              }

              final currentFlashMode = _controller?.value.flashMode;
              
              // Only turn ON after threshold frames of "needs flash"
              if (_flashConsistencyCounter >= _flashConsistencyThreshold) {
                if (currentFlashMode != FlashMode.always) {
                  _controller?.setFlashMode(FlashMode.always).catchError((e) => debugPrint('AutoFlash (Always) error: $e'));
                }
                // Keep at threshold to avoid overflow and allow immediate decrement if signal changes
                _flashConsistencyCounter = _flashConsistencyThreshold;
              } 
              // Only turn OFF after threshold frames of "doesn't need flash"
              else if (_flashConsistencyCounter <= -_flashConsistencyThreshold) {
                if (currentFlashMode != FlashMode.off) {
                  _controller?.setFlashMode(FlashMode.off).catchError((e) => debugPrint('AutoFlash (Off) error: $e'));
                }
                // Keep at -threshold
                _flashConsistencyCounter = -_flashConsistencyThreshold;
              }
            } else {
              // Reset counter if not in auto mode or no exposure result
              _flashConsistencyCounter = 0;
            }
            
            // Handle shutter pulse animation based on framing score
            if (_framingScoreResult != null && _framingScoreResult!.isGreat) {
              if (!_shutterPulseController.isAnimating) {
                _shutterPulseController.repeat(reverse: true);
              }
            } else {
              if (_shutterPulseController.isAnimating) {
                _shutterPulseController.stop();
                _shutterPulseController.reset();
              }
            }
            
            _lastDisplayFaceCenter = displayFaceCenter;
            _lastDisplayImageSize = displayImageSize;
          });
        }
        
        // Auto-shutter logic
        _handleAutoShutter(
          _distanceCoachingResult,
          _compositionGuidanceResult,
          _faceExposureResult,
          _blinkDetectionResult,
        );
        
        // Debug logging
        if (_frameCounter % 30 == 0 && faces.isNotEmpty) {
          if (_compositionGuidanceResult != null) {
            debugPrint('COMPOSITION DEBUG: Face center ($_lastDisplayFaceCenter) | Size ($_lastDisplayImageSize) | Nearest PP: (${_compositionGuidanceResult!.nearestPowerPoint.x.toStringAsFixed(3)}, ${_compositionGuidanceResult!.nearestPowerPoint.y.toStringAsFixed(3)}) | Distance: ${_compositionGuidanceResult!.distancePercentage.toStringAsFixed(3)} | Status: ${_compositionGuidanceResult!.status}');
          }
        }
    } catch (e) {
      if (_frameCounter % 50 == 0) {
        debugPrint('Error processing image for face detection: $e');
      }
    } finally {
      _isProcessing = false;
    }
  }

  void _handleAutoShutter(
    DistanceCoachingResult? coaching,
    CompositionGuidanceResult? composition,
    FaceExposureResult? exposure,
    BlinkDetectionResult? blink,
  ) {
    if (!appSettings.autoShutterEnabled || _isCapturing) {
      _goodFrameCount = 0;
      return;
    }

    // Check if any coaching features are enabled.
    // Auto-shutter depends on these.
    bool distanceEnabled = appSettings.distanceCoachingEnabled;
    bool compositionEnabled = appSettings.compositionGridEnabled;
    bool lightingEnabled = appSettings.lightingIntelligenceEnabled;
    bool orientationEnabled = appSettings.orientationSuggestionEnabled;
    
    // Safety check: if all are disabled, auto-shutter shouldn't be running.
    // The AppSettings logic already auto-disables autoShutterEnabled in this case,
    // but we keep this for extra robustness.
    if (!distanceEnabled && !compositionEnabled && !lightingEnabled && !orientationEnabled) {
      _goodFrameCount = 0;
      return;
    }

    // Check cooldown
    if (_lastAutoCaptureTime != null) {
      if (DateTime.now().difference(_lastAutoCaptureTime!) < _autoShutterCooldown) {
        return;
      }
    }

    // Auto-shutter criteria:
    // 1. If distance coaching is enabled, status must be optimal.
    // 2. If composition guidance is enabled, status must be wellPositioned.
    // 3. If orientation suggestion is enabled, there must be no mismatch.
    // 4. If blink detection is active, eyes must be open.
    
    bool isDistanceGood = !distanceEnabled || (coaching != null && coaching.status == DistanceCoachingStatus.optimal);
    
    // In landscape and multi-face mode, composition should be turned off automatically
    // (not in settings but logically).
    // TODO: Explore how composition coaching should work for groups (multi-face)
    final bool isLandscape = _stableLayoutOrientation == NativeDeviceOrientation.landscapeLeft ||
        _stableLayoutOrientation == NativeDeviceOrientation.landscapeRight;
    final bool isMultiFaceGroup = _significantFaceCount >= 2;
    final bool shouldIgnoreComposition = isLandscape && isMultiFaceGroup;

    bool isCompositionGood = !compositionEnabled || 
                             shouldIgnoreComposition || 
                             (composition != null && composition.status == CompositionStatus.wellPositioned);
    
    bool isLightingGood = !lightingEnabled || (exposure != null && exposure.status == ExposureStatus.good);
    
    // Blink detection requirement
    bool isBlinkGood = !appSettings.eyesClosedDetectionEnabled ||
        blink == null ||
        blink.canShoot;

    // For orientation, we still use it if enabled
    bool isOrientationGood = true;
    if (appSettings.orientationSuggestionEnabled) {
      final orientationGuidance = OrientationGuidance.evaluate(
        significantFaceCount: _significantFaceCount,
        currentOrientation: _stableLayoutOrientation,
      );
      isOrientationGood = !orientationGuidance.isMismatch;
    }

    if (isDistanceGood && isCompositionGood && isOrientationGood && isLightingGood && isBlinkGood) {
      _goodFrameCount++;
      if (_goodFrameCount >= _autoShutterRequiredGoodFrames) {
        _goodFrameCount = 0;
        _lastAutoCaptureTime = DateTime.now();
        _takePicture();
      }
    } else {
      _goodFrameCount = 0;
    }
  }

  void _handleFaceExposureLock(Face face, int rotationDegrees, Size imageSize) {
    if (_controller == null || !_controller!.value.isInitialized) return;

    // Check if we already locked on this face recently to avoid constant updates
    if (_lockedFace != null && _lastLockTime != null) {
      final now = DateTime.now();
      if (now.difference(_lastLockTime!) < _lockThreshold) {
        // If face moved significantly, update anyway
        final prevCenter = Offset(
          _lockedFace!.boundingBox.left + _lockedFace!.boundingBox.width / 2,
          _lockedFace!.boundingBox.top + _lockedFace!.boundingBox.height / 2,
        );
        final currentCenter = Offset(
          face.boundingBox.left + face.boundingBox.width / 2,
          face.boundingBox.top + face.boundingBox.height / 2,
        );
        if ((prevCenter - currentCenter).distance < 20) {
          return;
        }
      }
    }

    _lockedFace = face;
    _lastLockTime = DateTime.now();

    // ML Kit bounding box is in its "upright" image space (after rotation).
    // The camera plugin expects (0,0) top-left to (1,1) bottom-right of the sensor.
    // We need to map ML Kit's upright coordinates back to sensor coordinates.
    
    final camW = imageSize.width;
    final camH = imageSize.height;

    // Upright size as ML Kit sees it
    Size effectiveSize;
    if (rotationDegrees == 90 || rotationDegrees == 270) {
      effectiveSize = Size(camH, camW);
    } else {
      effectiveSize = Size(camW, camH);
    }

    final rawFaceCenterX = face.boundingBox.left + (face.boundingBox.width / 2);
    final rawFaceCenterY = face.boundingBox.top + (face.boundingBox.height / 2);

    // Normalize in upright space
    final nx = rawFaceCenterX / effectiveSize.width;
    final ny = rawFaceCenterY / effectiveSize.height;

    // Map back to sensor coordinates (normalized)
    double sx, sy;
    if (rotationDegrees == 90) {
      // Upright (x, y) = Sensor (H-y, x) -> (nx, ny) = ((H-sy)/H, sx/W)
      // nx = 1 - sy => sy = 1 - nx
      // ny = sx => sx = ny
      sx = ny;
      sy = 1.0 - nx;
    } else if (rotationDegrees == 180) {
      // Upright (x, y) = Sensor (W-x, H-y) -> (nx, ny) = ((W-sx)/W, (H-sy)/H)
      // nx = 1 - sx => sx = 1 - nx
      // ny = 1 - sy => sy = 1 - ny
      sx = 1.0 - nx;
      sy = 1.0 - ny;
    } else if (rotationDegrees == 270) {
      // Upright (x, y) = Sensor (y, W-x) -> (nx, ny) = (sy/H, (W-sx)/W)
      // nx = sy => sy = nx
      // ny = 1 - sx => sx = 1 - ny
      sx = 1.0 - ny;
      sy = nx;
    } else {
      sx = nx;
      sy = ny;
    }

    Offset focusPoint = Offset(sx.clamp(0.0, 1.0), sy.clamp(0.0, 1.0));

    try {
      _controller!.setExposurePoint(focusPoint);
      _controller!.setFocusPoint(focusPoint);
    } catch (e) {
      debugPrint('Error setting exposure/focus point: $e');
    }
  }

  /// Select the best face from multiple detected faces
  /// Uses a combination of size (70% weight) and centrality (30% weight)
  /// Faces closer to center and larger are preferred
  Face? _selectBestFace(List<Face> faces, Size imageSize) {
    if (faces.isEmpty) return null;
    if (faces.length == 1) return faces.first;
    
    final imageCenterX = imageSize.width / 2;
    final imageCenterY = imageSize.height / 2;
    
    Face? bestFace;
    double bestScore = -1;
    
    for (final face in faces) {
      // Calculate face area (normalized to 0-1 range, assuming max face is ~50% of image)
      final faceArea = face.boundingBox.width * face.boundingBox.height;
      final maxPossibleArea = imageSize.width * imageSize.height * 0.5;
      final normalizedArea = (faceArea / maxPossibleArea).clamp(0.0, 1.0);
      
      // Calculate face center
      final faceCenterX = face.boundingBox.left + (face.boundingBox.width / 2);
      final faceCenterY = face.boundingBox.top + (face.boundingBox.height / 2);
      
      // Calculate distance from image center (normalized to 0-1, where 0 = center, 1 = corner)
      final distanceFromCenterX = (faceCenterX - imageCenterX).abs() / imageCenterX;
      final distanceFromCenterY = (faceCenterY - imageCenterY).abs() / imageCenterY;
      final distanceFromCenter = sqrt(distanceFromCenterX * distanceFromCenterX + distanceFromCenterY * distanceFromCenterY);
      final normalizedDistance = distanceFromCenter.clamp(0.0, 1.0);
      
      // Centrality score (closer to center = higher score)
      final centralityScore = 1.0 - normalizedDistance;
      
      // Combined score: 70% size, 30% centrality
      // Add small bonus if this face is close to the previously tracked face (stability)
      double stabilityBonus = 0.0;
      if (_lastTrackedFaceBounds != null) {
        final currentCenterX = face.boundingBox.left + (face.boundingBox.width / 2);
        final currentCenterY = face.boundingBox.top + (face.boundingBox.height / 2);
        final lastCenterX = _lastTrackedFaceBounds!.left + (_lastTrackedFaceBounds!.width / 2);
        final lastCenterY = _lastTrackedFaceBounds!.top + (_lastTrackedFaceBounds!.height / 2);
        
        final distanceFromLast = sqrt(
          (currentCenterX - lastCenterX) * (currentCenterX - lastCenterX) +
          (currentCenterY - lastCenterY) * (currentCenterY - lastCenterY)
        );
        // Bonus if within 20% of image size from last face (10% of score)
        if (distanceFromLast < imageSize.width * 0.2) {
          stabilityBonus = 0.1 * (1.0 - (distanceFromLast / (imageSize.width * 0.2)));
        }
      }
      
      final score = (normalizedArea * 0.7) + (centralityScore * 0.3) + stabilityBonus;
      
      if (score > bestScore) {
        bestScore = score;
        bestFace = face;
      }
    }
    
    // Update tracked face bounds for next frame
    if (bestFace != null) {
      _lastTrackedFaceBounds = bestFace.boundingBox;
    }
    
    return bestFace;
  }

  /// Scale face rect for debug overlay using same transformation as FaceDetectorPainter
  Rect? _scaleFaceRectForDebug(
    Rect faceRect,
    Size imageSize,
    Size widgetSize,
    int rotationDegrees,
    NativeDeviceOrientation deviceOrientation,
    CameraLensDirection? cameraLensDirection,
  ) {
    if (imageSize.width == 0 || imageSize.height == 0) return null;
    
    // Use the same transformation logic as FaceDetectorPainter._scaleRect
    // ML Kit returns coordinates in the rotated (upright) image space.
    Size effectiveImageSize;
    if (rotationDegrees == 90 || rotationDegrees == 270) {
      effectiveImageSize = Size(imageSize.height, imageSize.width);
    } else {
      effectiveImageSize = Size(imageSize.width, imageSize.height);
    }

    // 1. Normalize coordinates (0 to 1)
    double nx = faceRect.left / effectiveImageSize.width;
    double ny = faceRect.top / effectiveImageSize.height;
    double nw = faceRect.width / effectiveImageSize.width;
    double nh = faceRect.height / effectiveImageSize.height;

    // 2. Map from ML Kit's "upright" space to the "portrait" preview space
    double finalNx, finalNy, finalNw, finalNh;

    int degrees = 0;
    switch (deviceOrientation) {
      case NativeDeviceOrientation.landscapeRight:
        degrees = 90;
        break;
      case NativeDeviceOrientation.portraitDown:
        degrees = 180;
        break;
      case NativeDeviceOrientation.landscapeLeft:
        degrees = 270;
        break;
      default:
        degrees = 0;
    }

    // Apply rotation to normalized coordinates
    if (degrees == 90) {
      finalNx = ny;
      finalNy = 1.0 - (nx + nw);
      finalNw = nh;
      finalNh = nw;
    } else if (degrees == 180) {
      finalNx = 1.0 - (nx + nw);
      finalNy = 1.0 - (ny + nh);
      finalNw = nw;
      finalNh = nh;
    } else if (degrees == 270) {
      finalNx = 1.0 - (ny + nh);
      finalNy = nx;
      finalNw = nh;
      finalNh = nw;
    } else {
      finalNx = nx;
      finalNy = ny;
      finalNw = nw;
      finalNh = nh;
    }

    // 3. Handle mirroring for front camera
    if (cameraLensDirection == CameraLensDirection.front) {
      if (deviceOrientation == NativeDeviceOrientation.landscapeLeft ||
          deviceOrientation == NativeDeviceOrientation.landscapeRight) {
        finalNy = 1.0 - (finalNy + finalNh);
      } else {
        finalNx = 1.0 - (finalNx + finalNw);
      }
    }

    // 4. Scale to widget size
    return Rect.fromLTWH(
      finalNx * widgetSize.width,
      finalNy * widgetSize.height,
      finalNw * widgetSize.width,
      finalNh * widgetSize.height,
    );
  }

  /// Handle tap to focus
  Future<void> _handleTapToFocus(TapDownDetails details, Size previewSize) async {
    if (_controller == null || !_controller!.value.isInitialized) {
      return;
    }
    
    try {
      // Get the local position relative to the preview box using GlobalKey for precision
      final RenderBox? renderBox = _previewKey.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox == null) return;
      
      final Offset localPosition = renderBox.globalToLocal(details.globalPosition);
      
      // Calculate normalized position (0-1 range) for the camera plugin
      final normalizedX = localPosition.dx / renderBox.size.width;
      final normalizedY = localPosition.dy / renderBox.size.height;
      
      Offset focusPoint = Offset(normalizedX, normalizedY);
      
      // For front camera on iOS, mirror x coordinate
      if (_currentCamera?.lensDirection == CameraLensDirection.front && Platform.isIOS) {
        focusPoint = Offset(1.0 - normalizedX, normalizedY);
      }
      
      // Clamp to valid range
      focusPoint = Offset(
        focusPoint.dx.clamp(0.0, 1.0),
        focusPoint.dy.clamp(0.0, 1.0),
      );
      
      // Show focus feedback ring immediately for better responsiveness
      setState(() {
        _focusPoint = localPosition;
        _focusAnimationController?.reset();
        _focusAnimationController?.forward();
      });
      
      // Hide focus ring after animation
      _focusTimer?.cancel();
      _focusTimer = Timer(const Duration(milliseconds: 1000), () {
        if (mounted) {
          setState(() {
            _focusPoint = null;
          });
        }
      });

      await _controller!.setFocusPoint(focusPoint);
    } catch (e) {
      debugPrint('Error handling tap to focus: $e');
    }
  }

  /// Sample frame pixels to detect if frame changed (for skipping face detection when stationary)
  Uint8List _sampleFrame(CameraImage image) {
    // Sample pixels in a grid pattern (e.g., every 20th pixel)
    // This gives us a lightweight way to detect frame changes
    const int sampleStep = 20;
    final List<int> samples = [];
    
    // Sample from the Y plane (luminance) - first plane in NV21/YUV420
    final plane = image.planes[0];
    final bytesPerRow = plane.bytesPerRow;
    
    for (int y = 0; y < image.height; y += sampleStep) {
      for (int x = 0; x < image.width; x += sampleStep) {
        // For Y plane, typically 1 byte per pixel
        final index = (y * bytesPerRow) + x;
        if (index < plane.bytes.length) {
          samples.add(plane.bytes[index]);
        }
      }
    }
    
    return Uint8List.fromList(samples);
  }
  
  /// Check if frame changed significantly (2% threshold) by comparing pixel samples
  bool _shouldProcessFrame(CameraImage image, Size imageSize) {
    // First frame or image size changed, always process
    if (_previousFrameSample == null || 
        _previousImageSize == null ||
        _previousImageSize!.width != imageSize.width ||
        _previousImageSize!.height != imageSize.height) {
      return true;
    }
    
    // Sample current frame
    final currentSample = _sampleFrame(image);
    
    if (currentSample.length != _previousFrameSample!.length) {
      return true; // Sample size mismatch, process frame
    }
    
    // Calculate difference percentage
    int totalDifference = 0;
    for (int i = 0; i < currentSample.length; i++) {
      totalDifference += (currentSample[i] - _previousFrameSample![i]).abs();
    }
    
    // Average difference per pixel (0-255 range)
    final avgDifference = totalDifference / currentSample.length;
    // Convert to percentage (255 = 100%)
    final differencePercentage = (avgDifference / 255.0) * 100.0;
    
    // Process if difference is >= 2%
    return differencePercentage >= 2.0;
  }

  int _calculateRotationDegrees() {
    final camera = _currentCamera;
    if (camera == null) return 0;

    int degrees = 0;
    switch (_deviceOrientation) {
      case NativeDeviceOrientation.portraitUp:
        degrees = 0;
        break;
      case NativeDeviceOrientation.landscapeLeft:
        degrees = 270;
        break;
      case NativeDeviceOrientation.portraitDown:
        degrees = 180;
        break;
      case NativeDeviceOrientation.landscapeRight:
        degrees = 90;
        break;
      case NativeDeviceOrientation.unknown:
        degrees = 0;
        break;
    }

    int sensorOrientation = camera.sensorOrientation;
    if (camera.lensDirection == CameraLensDirection.front) {
      return (sensorOrientation - degrees + 360) % 360;
    } else {
      return (sensorOrientation + degrees) % 360;
    }
  }

  InputImage? _convertCameraImage(CameraImage image, int rotationDegrees) {
    final camera = _controller?.description;
    if (camera == null) return null;

    // Combine all image planes into a single Uint8List
    final WriteBuffer allBytes = WriteBuffer();
    for (final plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();

    // Get image size
    final Size imageSize = Size(image.width.toDouble(), image.height.toDouble());

    final InputImageRotation imageRotation =
        InputImageRotationValue.fromRawValue(rotationDegrees) ??
        InputImageRotation.rotation0deg;

    // Determine image format based on platform
    // Android uses NV21, iOS uses YUV420
    // ML Kit on iOS can handle YUV420 format directly
    final InputImageFormat inputImageFormat = Platform.isAndroid
        ? InputImageFormat.nv21
        : InputImageFormat.yuv420;

    // Create InputImageMetadata (updated API)
    final InputImageMetadata metadata = InputImageMetadata(
      size: imageSize,
      rotation: imageRotation,
      format: inputImageFormat,
      bytesPerRow: image.planes.first.bytesPerRow,
    );

    // Create and return InputImage
    return InputImage.fromBytes(bytes: bytes, metadata: metadata);
  }

  int _getPreviewRotationTurns() {
    switch (_stableLayoutOrientation) {
      case NativeDeviceOrientation.landscapeLeft:
        return 1;
      case NativeDeviceOrientation.landscapeRight:
        return 3;
      case NativeDeviceOrientation.portraitDown:
        return 2;
      default:
        return 0;
    }
  }

  int _getIconRotationQuarterTurns() {
    return _getPreviewRotationTurns();
  }

  /// Apply bokeh (background blur) effect to a captured image using selfie segmentation
  Future<Uint8List> _applyBokehEffect(String imagePath) async {
    if (_selfieSegmenter == null) {
      throw Exception('Selfie segmenter not initialized');
    }

    // Read the image file
    final imageBytes = await File(imagePath).readAsBytes();
    final originalImage = img.decodeImage(imageBytes);
    if (originalImage == null) {
      throw Exception('Failed to decode image');
    }

    // Convert to InputImage for ML Kit
    final inputImage = InputImage.fromFilePath(imagePath);
    
    // Process with selfie segmentation
    final mask = await _selfieSegmenter!.processImage(inputImage);
    if (mask == null) {
      debugPrint('[_applyBokehEffect] No mask generated, returning original image');
      return imageBytes;
    }

    // Get mask dimensions
    final maskWidth = mask.width;
    final maskHeight = mask.height;
    
    // In google_mlkit_selfie_segmentation 0.10.0, the mask is provided as a List<double> of confidences
    final maskData = mask.confidences;

    // Scale mask to match image dimensions
    final imageWidth = originalImage.width;
    final imageHeight = originalImage.height;
    
    // Create a blurred version of the image
    final blurredImage = img.copyResize(
      originalImage,
      width: (imageWidth * 0.5).round(), // Downscale for faster blur
      height: (imageHeight * 0.5).round(),
    );
    final blurredFull = img.gaussianBlur(img.copyResize(blurredImage, width: imageWidth, height: imageHeight), radius: 15);

    // Apply mask: blend original (foreground) with blurred (background)
    final result = img.Image(width: imageWidth, height: imageHeight);
    
    for (int y = 0; y < imageHeight; y++) {
      for (int x = 0; x < imageWidth; x++) {
        // Get mask value at this position (scale from mask size to image size)
        final maskX = (x * maskWidth / imageWidth).round().clamp(0, maskWidth - 1);
        final maskY = (y * maskHeight / imageHeight).round().clamp(0, maskHeight - 1);
        final maskIndex = maskY * maskWidth + maskX;
        // Mask value is already 0.0-1.0 (float), where 1.0 = foreground confidence
        final maskValue = maskData[maskIndex].clamp(0.0, 1.0);
        
        // Get original and blurred pixel colors
        final originalColor = originalImage.getPixel(x, y);
        final blurredColor = blurredFull.getPixel(x, y);
        
        // Extract color channels - use Color class properties
        final originalR = originalColor.r;
        final originalG = originalColor.g;
        final originalB = originalColor.b;
        final originalA = originalColor.a;
        
        final blurredR = blurredColor.r;
        final blurredG = blurredColor.g;
        final blurredB = blurredColor.b;
        
        // Blend: use original for foreground (high mask value), blurred for background (low mask value)
        // maskValue is already 0.0-1.0 where 1.0 = foreground
        final blendFactor = maskValue;
        final r = (originalR * blendFactor + blurredR * (1 - blendFactor)).round();
        final g = (originalG * blendFactor + blurredG * (1 - blendFactor)).round();
        final b = (originalB * blendFactor + blurredB * (1 - blendFactor)).round();
        
        result.setPixel(x, y, img.ColorRgba8(r, g, b, originalA.toInt()));
      }
    }

    // Encode back to JPEG
    final outputBytes = Uint8List.fromList(img.encodeJpg(result, quality: 95));
    return outputBytes;
  }

  /// JPEG snapshot for AI (no gallery save). Restores the image stream when it was active.
  Future<Uint8List?> _capturePreviewJpegBytes() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return null;
    }

    final wasStreaming = controller.value.isStreamingImages;
    if (wasStreaming) {
      try {
        await controller.stopImageStream();
      } catch (e) {
        debugPrint('[_capturePreviewJpegBytes] stopImageStream: $e');
      }
    }

    try {
      final XFile shot = await controller.takePicture();
      final Uint8List raw = await File(shot.path).readAsBytes();
      try {
        await File(shot.path).delete();
      } catch (_) {}
      return _downscaleJpegForAi(raw);
    } catch (e) {
      debugPrint('[_capturePreviewJpegBytes] takePicture: $e');
      return null;
    } finally {
      if (controller.value.isInitialized &&
          wasStreaming &&
          !controller.value.isStreamingImages) {
        try {
          await controller.startImageStream(_processCameraImage);
        } catch (e) {
          debugPrint('[_capturePreviewJpegBytes] restart stream: $e');
        }
      }
    }
  }

  Uint8List? _downscaleJpegForAi(Uint8List raw) {
    try {
      final decoded = img.decodeImage(raw);
      if (decoded == null) return raw;
      const int maxSide = 1024;
      if (decoded.width <= maxSide && decoded.height <= maxSide) return raw;
      final img.Image resized = decoded.width >= decoded.height
          ? img.copyResize(decoded, width: maxSide)
          : img.copyResize(decoded, height: maxSide);
      return Uint8List.fromList(img.encodeJpg(resized, quality: 88));
    } catch (e) {
      debugPrint('[_downscaleJpegForAi] $e');
      return raw;
    }
  }

  Future<void> _requestAiFramingAdvice() async {
    if (_isAiAdviceLoading ||
        _isCapturing ||
        _controller == null ||
        !_controller!.value.isInitialized) {
      return;
    }

    setState(() => _isAiAdviceLoading = true);

    String? adviceText;
    String? errorMessage;

    try {
      final bytes = await _capturePreviewJpegBytes();
      if (bytes == null || bytes.isEmpty) {
        errorMessage = 'Impossibile acquisire l\'immagine. Riprova.';
      } else {
        final model = FirebaseAI.googleAI().generativeModel(
          model: 'gemini-2.5-flash-lite',
          generationConfig: GenerationConfig(
            maxOutputTokens: 220,
            temperature: 0.35,
          ),
        );

        final prompt = TextPart(
          'Sei un coach di fotografia mobile. Guarda questa immagine dalla fotocamera del telefono. '
          'Rispondi in italiano con un consiglio breve e concreto (massimo 2–3 frasi) su come '
          'spostare o inclinare il telefono, inquadrare o regolare la posizione per una foto migliore '
          '(composizione, luce, distanza, orizzonte). Non descrivere la scena a lungo: concentrati solo su cosa fare.',
        );
        final imagePart = InlineDataPart('image/jpeg', bytes);

        final response = await model.generateContent([
          Content.multi([prompt, imagePart]),
        ]);

        try {
          adviceText = response.text?.trim();
        } on FirebaseAIException catch (e) {
          errorMessage = e.message;
        }

        if (errorMessage == null &&
            (adviceText == null || adviceText.isEmpty)) {
          errorMessage = 'Nessuna risposta dal modello. Riprova.';
        }
      }
    } on FirebaseAIException catch (e) {
      errorMessage = e.message;
    } catch (e) {
      debugPrint('[_requestAiFramingAdvice] $e');
      errorMessage = 'Errore di rete o del servizio. Riprova tra poco.';
    } finally {
      if (mounted) {
        setState(() => _isAiAdviceLoading = false);
      }
    }

    if (!mounted) return;

    if (errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage)),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('AI advice'),
        content: SingleChildScrollView(
          child: Text(adviceText ?? ''),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _buildAiAdviceButton() {
    return GestureDetector(
      onTap: _isAiAdviceLoading ? null : _requestAiFramingAdvice,
      child: RotatedBox(
        quarterTurns: _getIconRotationQuarterTurns(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.25),
              width: 1,
            ),
          ),
          child: _isAiAdviceLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome, color: Colors.amberAccent, size: 18),
                    SizedBox(width: 6),
                    Text(
                      'AI advice',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildFlashButton() {
    IconData icon;
    Color color = Colors.white;
    switch (appSettings.flashMode) {
      case FlashModeSetting.off:
        icon = Icons.flash_off;
        color = Colors.white54;
        break;
      case FlashModeSetting.on:
        icon = Icons.flash_on;
        color = Colors.yellow;
        break;
      case FlashModeSetting.auto:
        icon = Icons.flash_auto;
        color = Colors.blueAccent;
        break;
    }

    return GestureDetector(
      onTap: () {
        final current = appSettings.flashMode;
        FlashModeSetting next;
        if (current == FlashModeSetting.auto) {
          next = FlashModeSetting.on;
        } else if (current == FlashModeSetting.on) {
          next = FlashModeSetting.off;
        } else {
          next = FlashModeSetting.auto;
        }
        appSettings.flashMode = next;
      },
      child: RotatedBox(
        quarterTurns: _getIconRotationQuarterTurns(),
        child: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.5),
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
          child: Icon(
            icon,
            color: color,
            size: 24,
          ),
        ),
      ),
    );
  }

  Future<void> _switchCamera() async {
    if (_cameras == null || _cameras!.length < 2 || _isProcessing || _isCapturing) return;

    final lensDirection = _currentCamera?.lensDirection == CameraLensDirection.back
        ? CameraLensDirection.front
        : CameraLensDirection.back;

    final newCamera = _cameras!.firstWhere(
      (camera) => camera.lensDirection == lensDirection,
      orElse: () => _cameras!.first,
    );

    if (newCamera == _currentCamera) return;

    // Show a quick fade to black to hide the transition "blink"
    setState(() {
      _isInitialized = false;
    });

    // Stop current stream before switching
    if (_controller != null && _controller!.value.isStreamingImages) {
      try {
        await _controller!.stopImageStream();
      } catch (e) {
        debugPrint('Error stopping image stream: $e');
      }
    }

    // Dispose old controller
    final oldController = _controller;
    _controller = null;
    await oldController?.dispose();

    _currentCamera = newCamera;
    
    // Update app settings with lens direction
    appSettings.setCameraLens(_currentCamera!.lensDirection == CameraLensDirection.front);
    
    _controller = CameraController(
      _currentCamera!,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid 
          ? ImageFormatGroup.nv21 
          : ImageFormatGroup.yuv420,
    );

    try {
      await _controller!.initialize();
      await _controller!.setFocusMode(FocusMode.auto);
      
      // Start streaming before setting _isInitialized to true
      // to ensure the first frame is ready when the UI rebuilds
      await _controller!.startImageStream(_processCameraImage);
      
      if (mounted) {
        setState(() {
          _isInitialized = true;
          _detectedFaces = []; // Clear old results
          _distanceCoachingResult = null;
          _compositionGuidanceResult = null;
        });
      }
    } catch (e) {
      debugPrint('Error switching camera: $e');
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasPermission) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.camera_alt_outlined,
                size: 64,
                color: Colors.white,
              ),
              const SizedBox(height: 16),
              const Text(
                'Camera permission required',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () async {
                  await openAppSettings();
                },
                child: const Text('Open Settings'),
              ),
            ],
          ),
        ),
      );
    }

    if (!_isInitialized || _controller == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(
                color: Colors.white,
              ),
              const SizedBox(height: 16),
              const Text(
                'Initializing camera...',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Calculate the correct aspect ratio for the preview container
    // Since the app is locked in portrait, we always want a portrait-proportioned container (e.g., 720/1280)
    // The content inside will be rotated to match the physical orientation
    double previewAspectRatio;
    if (_imageSize != null) {
      // imageSize is typically landscape (e.g., 1280x720), so ratio is 720/1280
      previewAspectRatio = _imageSize!.height / _imageSize!.width;
    } else {
      // Fallback to controller aspect ratio (inverted for portrait container)
      final controllerRatio = _controller!.value.aspectRatio;
      previewAspectRatio = controllerRatio > 1 ? 1 / controllerRatio : controllerRatio;
    }
    
    final orientationGuidance = appSettings.orientationSuggestionEnabled 
      ? OrientationGuidance.evaluate(
          significantFaceCount: _significantFaceCount,
          currentOrientation: _stableLayoutOrientation,
        )
      : const OrientationGuidance(isMismatch: false, suggestedOrientation: OrientationSuggestion.none);
    final isOrientationMismatch = orientationGuidance.isMismatch;
    
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera preview with overlays - centered with correct aspect ratio
          Center(
            child: AspectRatio(
              aspectRatio: previewAspectRatio,
              child: LayoutBuilder(
                builder: (context, portraitConstraints) {
                  final portraitPreviewSize = Size(portraitConstraints.maxWidth, portraitConstraints.maxHeight);
                  
                  return GestureDetector(
                    key: _previewKey,
                    onTapDown: (details) => _handleTapToFocus(details, portraitPreviewSize),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CameraPreview(_controller!),
                        // Face detection overlay
                        if (appSettings.faceDetectionEnabled)
                          CustomPaint(
                            painter: FaceDetectorPainter(
                              faces: _detectedFaces,
                              imageSize: _imageSize,
                              cameraPreviewSize: portraitPreviewSize,
                              rotationDegrees: _detectedFacesRotation,
                              deviceOrientation: _detectedFacesOrientation,
                              cameraLensDirection: _currentCamera?.lensDirection,
                            ),
                          ),
                        // Portrait debug overlay
                        if (appSettings.portraitDebugEnabled && _portraitAnalysisResult != null && _detectedFaces.isNotEmpty && _imageSize != null)
                          CustomPaint(
                            painter: PortraitDebugOverlay(
                              portraitResult: _portraitAnalysisResult,
                              imageSize: _imageSize!,
                              faceBoundingBox: _scaleFaceRectForDebug(
                                _detectedFaces.first.boundingBox,
                                _imageSize!,
                                portraitPreviewSize,
                                _detectedFacesRotation,
                                _detectedFacesOrientation,
                                _currentCamera?.lensDirection,
                              ),
                            ),
                          ),
                        // Composition grid overlay (inside preview area)
                        if (appSettings.compositionGridEnabled)
                          CompositionGridOverlay(
                            compositionResult: _compositionGuidanceResult,
                            distanceResult: _distanceCoachingResult,
                            previewSize: portraitPreviewSize,
                            deviceOrientation: _detectedFacesOrientation,
                            isOrientationMismatch: isOrientationMismatch && appSettings.orientationSuggestionEnabled,
                            significantFaceCount: _significantFaceCount,
                          ),
                        
                        // Focus feedback ring (in portrait coordinate space relative to preview)
                        if (_focusPoint != null && _focusAnimationController != null)
                          IgnorePointer(
                            child: AnimatedBuilder(
                              animation: _focusAnimation!,
                              builder: (context, child) {
                                // Shrink from 55 to 40 as it fades out
                                final double size = 40 + (15 * _focusAnimation!.value);
                                return Stack(
                                  children: [
                                    Positioned(
                                      left: _focusPoint!.dx - size / 2,
                                      top: _focusPoint!.dy - size / 2,
                                      child: Container(
                                        width: size,
                                        height: size,
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: Colors.white.withValues(alpha: _focusAnimation!.value),
                                            width: 1.5,
                                          ),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),

                        // AE/AF Lock Circle feedback (yellow circle)
                        if (_lockedFace != null && _lastDisplayFaceCenter != null && _lastDisplayImageSize != null)
                          Positioned(
                            left: (_lastDisplayFaceCenter!.dx * (portraitPreviewSize.width / _lastDisplayImageSize!.width)) - 25,
                            top: (_lastDisplayFaceCenter!.dy * (portraitPreviewSize.height / _lastDisplayImageSize!.height)) - 25,
                            child: Builder(
                              builder: (context) {
                                if (_frameCounter % 30 == 0) {
                                  final double left = (_lastDisplayFaceCenter!.dx * (portraitPreviewSize.width / _lastDisplayImageSize!.width)) - 25;
                                  final double top = (_lastDisplayFaceCenter!.dy * (portraitPreviewSize.height / _lastDisplayImageSize!.height)) - 25;
                                  debugPrint('AE_LOCK_CIRCLE_POS: Center (${left + 25}, ${top + 25}) on preview size $portraitPreviewSize');
                                }
                                return IgnorePointer(
                                  child: Container(
                                    width: 50,
                                    height: 50,
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: Colors.yellowAccent.withValues(alpha: 0.8),
                                        width: 2.0,
                                      ),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                );
                              }
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          
          // Top row controls (Settings, Flash)
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(
                    Icons.settings,
                    color: Colors.white,
                    size: 32,
                  ),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (context) => const SettingsScreen()),
                    );
                  },
                ),
                _buildFlashButton(),
              ],
            ),
          ),
          
          // Flash animation overlay
          AnimatedBuilder(
            animation: _flashAnimation,
            builder: (context, child) {
              return IgnorePointer(
                child: Container(
                  color: Colors.white.withValues(alpha: _flashAnimation.value * 0.8),
                ),
              );
            },
          ),
          
          // Coaching & Orientation overlay (rotates with orientation)
          CoachingOverlay(
            coachingResult: _distanceCoachingResult,
            compositionResult: _compositionGuidanceResult,
            exposureResult: _faceExposureResult,
            blinkResult: appSettings.eyesClosedDetectionEnabled
                ? _blinkDetectionResult
                : null,
            framingScore: _framingScoreResult,
            significantFaceCount: _significantFaceCount,
            deviceOrientation: _stableLayoutOrientation,
            isOrientationMismatch: isOrientationMismatch && appSettings.orientationSuggestionEnabled,
          ),
          
          // Portrait mode indicator
          PortraitIndicator(
            portraitResult: _portraitAnalysisResult,
            showDebugOverlay: appSettings.portraitDebugEnabled,
          ),
          
          // Bottom controls
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.7),
                    ],
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _buildThumbnailButton(),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildAiAdviceButton(),
                        const SizedBox(height: 8),
                        _buildShutterButton(),
                      ],
                    ),
                    _buildCameraSwitchButton(),
                  ],
                ),
              ),
            ),
          ),
          
          // Minimize animation overlay
          if (_minimizingImage != null && _previewButtonRect != null)
            AnimatedBuilder(
              animation: _minimizeAnimation,
              builder: (context, child) {
                final screenSize = MediaQuery.of(context).size;
                final startWidth = screenSize.width;
                final startHeight = screenSize.height;
                final endWidth = _previewButtonRect!.width;
                final endHeight = _previewButtonRect!.height;
                
                final currentWidth = startWidth - (startWidth - endWidth) * _minimizeAnimation.value;
                final currentHeight = startHeight - (startHeight - endHeight) * _minimizeAnimation.value;
                
                final startX = 0.0;
                final startY = 0.0;
                final endX = _previewButtonRect!.left;
                final endY = _previewButtonRect!.top;
                
                final currentX = startX + (endX - startX) * _minimizeAnimation.value;
                final currentY = startY + (endY - startY) * _minimizeAnimation.value;
                
                final opacity = 1.0 - (_minimizeAnimation.value * 0.3);
                
                return Positioned(
                  left: currentX,
                  top: currentY,
                  width: currentWidth,
                  height: currentHeight,
                  child: Opacity(
                    opacity: opacity,
                    child: Image.file(
                      _minimizingImage!,
                      fit: BoxFit.cover,
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildThumbnailButton() {
    return GestureDetector(
      onTap: () {
        if (_lastImageFile != null) {
          _showImagePreview(_lastImageFile!);
        }
      },
      child: RotatedBox(
        quarterTurns: _getIconRotationQuarterTurns(),
        child: Container(
          key: _previewButtonKey,
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.3),
              width: 2,
            ),
          ),
          child: _lastImageFile != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.file(
                    _lastImageFile!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return const Icon(
                        Icons.image_outlined,
                        color: Colors.white54,
                        size: 30,
                      );
                    },
                  ),
                )
              : const Icon(
                  Icons.image_outlined,
                  color: Colors.white54,
                  size: 30,
                ),
        ),
      ),
    );
  }

  Widget _buildShutterButton() {
    return GestureDetector(
      onTap: _isCapturing ? null : _takePicture,
      child: AnimatedBuilder(
        animation: _shutterPulseAnimation,
        builder: (context, child) {
          final isPulsing = _shutterPulseController.isAnimating;
          return Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isPulsing 
                ? Color.lerp(Colors.white, Colors.greenAccent, _shutterPulseAnimation.value) 
                : Colors.white,
              border: Border.all(
                color: isPulsing
                  ? Color.lerp(Colors.white30, Colors.green.withValues(alpha: 0.5), _shutterPulseAnimation.value)!
                  : Colors.white.withValues(alpha: 0.3),
                width: 4 + (isPulsing ? _shutterPulseAnimation.value * 2 : 0),
              ),
              boxShadow: [
                BoxShadow(
                  color: isPulsing
                    ? Colors.green.withValues(alpha: 0.3 * _shutterPulseAnimation.value)
                    : Colors.black.withValues(alpha: 0.3),
                  blurRadius: 10 + (isPulsing ? _shutterPulseAnimation.value * 5 : 0),
                  spreadRadius: 2 + (isPulsing ? _shutterPulseAnimation.value * 2 : 0),
                ),
              ],
            ),
            child: _isCapturing
                ? const Center(
                    child: SizedBox(
                      width: 30,
                      height: 30,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                      ),
                    ),
                  )
                : Container(
                    margin: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isPulsing 
                        ? Color.lerp(Colors.white, Colors.greenAccent, _shutterPulseAnimation.value) 
                        : Colors.white,
                    ),
                  ),
          );
        },
      ),
    );
  }

  Widget _buildCameraSwitchButton() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: IconButton(
        onPressed: _switchCamera,
        iconSize: 32,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(
          minWidth: 60,
          minHeight: 60,
        ),
        icon: RotatedBox(
          quarterTurns: _getIconRotationQuarterTurns(),
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.3),
                width: 2,
              ),
            ),
            child: const Icon(
              Icons.flip_camera_ios_outlined,
              color: Colors.white,
              size: 30,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showImagePreview(File imageFile) async {
    try {
      // Open the specific photo in the gallery app with swipe navigation
      if (Platform.isAndroid) {
        // Android: Construct MediaStore content URI directly from asset ID
        // This matches the React Native implementation which uses:
        // content://media/external/images/media/{assetId}
        if (_lastImageUri != null) {
          try {
            debugPrint('[_showImagePreview] Opening photo with asset ID: $_lastImageUri');
            
            // Method 1: Construct content URI manually (like React Native does)
            // The asset.id from photo_manager IS the MediaStore ID on Android
            final String contentUri = 'content://media/external/images/media/$_lastImageUri';
            debugPrint('[_showImagePreview] Constructed content URI: $contentUri');
            
            final intent = AndroidIntent(
              action: 'android.intent.action.VIEW',
              data: contentUri,
              type: 'image/jpeg',  // Use specific MIME type like React Native
              flags: <int>[
                Flag.FLAG_ACTIVITY_NEW_TASK,
                Flag.FLAG_GRANT_READ_URI_PERMISSION,
              ],
            );
            await intent.launch();
            debugPrint('[_showImagePreview] Successfully launched intent');
            return; // Successfully opened
          } catch (e) {
            debugPrint('[_showImagePreview] Error opening with constructed URI: $e');
            
            // Method 2: Try using getMediaUrl() as fallback
            try {
              final AssetEntity? asset = await AssetEntity.fromId(_lastImageUri!);
              if (asset != null) {
                final String? uri = await asset.getMediaUrl();
                debugPrint('[_showImagePreview] Got URI from getMediaUrl(): $uri');
                if (uri != null && uri.startsWith('content://')) {
                  final intent = AndroidIntent(
                    action: 'android.intent.action.VIEW',
                    data: uri,
                    type: 'image/jpeg',
                    flags: <int>[
                      Flag.FLAG_ACTIVITY_NEW_TASK,
                      Flag.FLAG_GRANT_READ_URI_PERMISSION,
                    ],
                  );
                  await intent.launch();
                  debugPrint('[_showImagePreview] Successfully launched with getMediaUrl()');
                  return;
                }
              }
            } catch (e2) {
              debugPrint('[_showImagePreview] Error with getMediaUrl() fallback: $e2');
            }
          }
        }
        
        // Fallback: Try opening the file directly with content URI
        try {
          // Try to get content URI from file path
          final result = await OpenFile.open(imageFile.path);
          if (result.type == ResultType.done) {
            return; // Successfully opened
          }
        } catch (e) {
          debugPrint('Error opening file: $e');
        }
        
        // Last fallback: Open gallery app
        final intent = AndroidIntent(
          action: 'android.intent.action.VIEW',
          type: 'image/*',
          flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
        );
        await intent.launch();
      } else if (Platform.isIOS) {
        // iOS: Open Photos app (iOS doesn't support opening specific photos via URL)
        const photosUri = 'photos-redirect://';
        final uri = Uri.parse(photosUri);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri);
        } else {
          // Fallback: try the standard photos URL
          const fallbackUri = 'photos://';
          final fallback = Uri.parse(fallbackUri);
          if (await canLaunchUrl(fallback)) {
            await launchUrl(fallback);
          } else {
            throw Exception('Cannot open Photos app');
          }
        }
      }
    } catch (e) {
      debugPrint('Error opening gallery: $e');
      // Fallback to showing in-app preview if opening fails
      if (mounted) {
        _showInAppPreview(imageFile);
      }
    }
  }

  void _showInAppPreview(File imageFile) {
    showDialog(
      context: context,
      barrierColor: Colors.black,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.zero,
          child: Stack(
            children: [
              // Full screen image
              Center(
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 3.0,
                  child: Image.file(
                    imageFile,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return const Center(
                        child: Text(
                          'Error loading image',
                          style: TextStyle(color: Colors.white),
                        ),
                      );
                    },
                  ),
                ),
              ),
              // Close button
              Positioned(
                top: MediaQuery.of(context).padding.top + 16,
                right: 16,
                child: IconButton(
                  icon: const Icon(
                    Icons.close,
                    color: Colors.white,
                    size: 32,
                  ),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// CustomPainter for drawing face detection outlines
class FaceDetectorPainter extends CustomPainter {
  final List<Face> faces;
  final Size? imageSize;
  final Size cameraPreviewSize;
  final int rotationDegrees;
  final NativeDeviceOrientation deviceOrientation;
  final CameraLensDirection? cameraLensDirection;

  static bool _hasLogged = false;

  FaceDetectorPainter({
    required this.faces,
    required this.imageSize,
    required this.cameraPreviewSize,
    required this.rotationDegrees,
    required this.deviceOrientation,
    this.cameraLensDirection,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (imageSize == null || faces.isEmpty) return;

    // Debug log once
    if (!_hasLogged) {
      _hasLogged = true;
      debugPrint('');
      debugPrint('🎨 PAINT DEBUG 🎨');
      debugPrint('Canvas size (display): $size');
      debugPrint('Image size (from camera): $imageSize');
      debugPrint('Rotation degrees: $rotationDegrees°');
      debugPrint('Camera preview size: $cameraPreviewSize');
      debugPrint('Lens direction: $cameraLensDirection');
      if (faces.isNotEmpty) {
        debugPrint('First face bounds (raw): ${faces.first.boundingBox}');
        final transformed = _scaleRect(
          rect: faces.first.boundingBox,
          imageSize: imageSize!,
          widgetSize: size,
        );
        debugPrint('First face bounds (transformed): $transformed');
      }
      debugPrint('');
    }

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.white.withValues(alpha: 0.4);

    for (final face in faces) {
      // Convert face bounding box from image coordinates to screen coordinates
      final rect = _scaleRect(
        rect: face.boundingBox,
        imageSize: imageSize!,
        widgetSize: size,
      );
      
      if (_frameCounter % 30 == 0) {
        debugPrint('FACE_DET_RECT: $rect on widget size $size');
      }

      // Draw rectangle around the face
      canvas.drawRect(rect, paint);

      // Note: Landmarks are NOT enabled in options, so we can't get exact eye positions.
      // Eye status markers could be added here if landmarks are enabled in the future.
    }
  }

  // Use a simple counter to throttle logs
  static int _frameCounter = 0;

  Rect _scaleRect({
    required Rect rect,
    required Size imageSize,
    required Size widgetSize,
  }) {
    // ML Kit returns coordinates in the rotated (upright) image space.
    // effectiveImageSize is the size of the image as ML Kit sees it.
    Size effectiveImageSize;
    if (rotationDegrees == 90 || rotationDegrees == 270) {
      effectiveImageSize = Size(imageSize.height, imageSize.width);
    } else {
      effectiveImageSize = Size(imageSize.width, imageSize.height);
    }

    // 1. Normalize coordinates (0 to 1)
    double nx = rect.left / effectiveImageSize.width;
    double ny = rect.top / effectiveImageSize.height;
    double nw = rect.width / effectiveImageSize.width;
    double nh = rect.height / effectiveImageSize.height;

    // 2. Map from ML Kit's "upright" space to the "portrait" preview space.
    // The CameraPreview is always in portrait and its content is rotated by sensorOrientation.
    // To match, we must counter-rotate by the device orientation.
    double finalNx, finalNy, finalNw, finalNh;

    int degrees = 0;
    switch (deviceOrientation) {
      case NativeDeviceOrientation.landscapeRight:
        degrees = 90;
        break;
      case NativeDeviceOrientation.portraitDown:
        degrees = 180;
        break;
      case NativeDeviceOrientation.landscapeLeft:
        degrees = 270;
        break;
      default:
        degrees = 0;
    }

    // Apply rotation to normalized coordinates
    if (degrees == 90) {
      // Rotate -90 degrees (or 270)
      finalNx = ny;
      finalNy = 1.0 - (nx + nw);
      finalNw = nh;
      finalNh = nw;
    } else if (degrees == 180) {
      // Rotate 180 degrees
      finalNx = 1.0 - (nx + nw);
      finalNy = 1.0 - (ny + nh);
      finalNw = nw;
      finalNh = nh;
    } else if (degrees == 270) {
      // Rotate -270 degrees (or 90)
      finalNx = 1.0 - (ny + nh);
      finalNy = nx;
      finalNw = nh;
      finalNh = nw;
    } else {
      // portraitUp
      finalNx = nx;
      finalNy = ny;
      finalNw = nw;
      finalNh = nh;
    }

    // 3. Handle mirroring for front camera
    if (cameraLensDirection == CameraLensDirection.front) {
      // For front camera, the preview is mirrored horizontally in the portrait coordinate space.
      if (deviceOrientation == NativeDeviceOrientation.landscapeLeft) {
        // Landscape Left: Rotate 270 (Counter-clockwise 90)
        // Mirrors along the vertical axis of the preview (which is the horizontal axis of the screen)
        finalNy = 1.0 - (finalNy + finalNh);
      } else if (deviceOrientation == NativeDeviceOrientation.landscapeRight) {
        // Landscape Right: Rotate 90
        finalNy = 1.0 - (finalNy + finalNh);
      } else {
        // Portrait
        finalNx = 1.0 - (finalNx + finalNw);
      }
    }

    // 4. Scale to widget size
    return Rect.fromLTWH(
      finalNx * widgetSize.width,
      finalNy * widgetSize.height,
      finalNw * widgetSize.width,
      finalNh * widgetSize.height,
    );
  }

  @override
  bool shouldRepaint(FaceDetectorPainter oldDelegate) => true;
}
