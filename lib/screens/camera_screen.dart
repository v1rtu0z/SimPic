import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:gallery_saver_plus/gallery_saver.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:open_file/open_file.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:native_device_orientation/native_device_orientation.dart';
import '../models/distance_coaching_scenario.dart';
import '../widgets/distance_coaching_overlay.dart';
import '../models/composition_guidance.dart';
import '../widgets/composition_grid_overlay.dart';

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
  String? _lastImagePath;
  File? _lastImageFile;
  String? _lastImageUri; // Content URI for opening in gallery
  GlobalKey _previewButtonKey = GlobalKey();
  
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
  List<Face> _detectedFaces = [];
  bool _isProcessing = false;
  int _frameCounter = 0;
  Size? _imageSize;
  
  // Orientation tracking
  NativeDeviceOrientation _deviceOrientation = NativeDeviceOrientation.portraitUp;
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
  
  // Focus feedback
  Offset? _focusPoint;
  AnimationController? _focusAnimationController;
  Animation<double>? _focusAnimation;
  Timer? _focusTimer;
  
  // Face tracking for stability in distance coaching (used in _selectBestFace)
  Rect? _lastTrackedFaceBounds;
  
  // Frame comparison for stability (skip face detection when camera is stationary)
  Uint8List? _previousFrameSample;
  Size? _previousImageSize;
  int _currentRotationDegrees = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // Listen to physical device orientation changes using sensors
    _orientationSubscription = NativeDeviceOrientationCommunicator()
        .onOrientationChanged(useSensor: true)
        .listen((orientation) {
      if (mounted) {
        setState(() {
          _deviceOrientation = orientation;
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
        enableClassification: false,
        enableLandmarks: false,
        enableTracking: false,
        performanceMode: FaceDetectorMode.accurate,
      ),
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
    
    _initializeCamera();
    _loadLatestPhoto();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _orientationSubscription?.cancel();
    _controller?.dispose();
    _flashAnimationController.dispose();
    _minimizeAnimationController.dispose();
    _focusAnimationController?.dispose();
    _focusTimer?.cancel();
    _faceDetector?.close();
    super.dispose();
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

    // Request storage permission for saving photos
    if (Platform.isAndroid) {
      final storageStatus = await Permission.storage.request();
      if (storageStatus.isDenied) {
        // Try photos permission for Android 13+
        await Permission.photos.request();
      }
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
      debugPrint('[_loadLatestPhoto] Requesting photo permission...');
      final PermissionState permission = await PhotoManager.requestPermissionExtend();
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

  Future<void> _takePicture() async {
    if (_controller == null || !_controller!.value.isInitialized || _isCapturing) {
      return;
    }

    setState(() {
      _isCapturing = true;
    });

    try {
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

      // Save to gallery and get the asset ID directly
      // This matches React Native's MediaLibrary.createAssetAsync() behavior
      String? savedImageUri;
      File? savedImageFile;
      try {
        debugPrint('[_takePicture] Saving image to gallery...');
        
        // Use photo_manager to save and get the asset ID directly
        // This is more reliable than gallery_saver_plus + querying
        final PermissionState permission = await PhotoManager.requestPermissionExtend();
        if (!permission.hasAccess) {
          throw Exception('Photo permission not granted');
        }
        
        // Read the image file as bytes
        final File imageFile = File(image.path);
        final Uint8List imageBytes = await imageFile.readAsBytes();
        
        // Save using photo_manager editor - returns AssetEntity with ID directly
        // On Android: Save to DCIM/Camera directory (standard camera photos location)
        // On iOS: relativePath is ignored, photos are saved to Camera Roll automatically
        final AssetEntity? savedAsset = Platform.isAndroid
            ? await PhotoManager.editor.saveImage(
                imageBytes,
                filename: path.basename(image.path),
                relativePath: 'DCIM/Camera',
              )
            : await PhotoManager.editor.saveImage(
                imageBytes,
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
        
        debugPrint('Photo saved to gallery successfully');
      } catch (e) {
        debugPrint('Error saving to gallery: $e');
        // If saving fails, still use the original temp file
        setState(() {
          _lastImagePath = image.path;
          _lastImageFile = File(image.path);
        });
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
      
      setState(() {
        _isCapturing = false;
      });
    }
  }

  Future<void> _processCameraImage(CameraImage image) async {
    // Skip frames for optimization (process every 2nd frame for more real-time feel)
    _frameCounter++;
    // if (_frameCounter % 2 != 0) {
    //   return;
    // }

    // Skip if already processing to prevent queue buildup
    if (_isProcessing || _faceDetector == null) {
      return;
    }

    _isProcessing = true;

    try {
      final imageSize = Size(image.width.toDouble(), image.height.toDouble());
      
      // Check if frame changed significantly before running face detection
      final shouldRunFaceDetection = _shouldProcessFrame(image, imageSize);
      
      List<Face> faces = [];
      DistanceCoachingResult? coachingResult;
      
      if (shouldRunFaceDetection) {
        // Frame changed significantly, run face detection
        final inputImage = _convertCameraImage(image);
        if (inputImage == null) {
          _isProcessing = false;
          debugPrint('Failed to convert camera image');
          return;
        }
        
        faces = await _faceDetector!.processImage(inputImage);
        
        // Store frame sample for next comparison
        _previousFrameSample = _sampleFrame(image);
        _previousImageSize = imageSize;
        
        int significantFaceCount = 0;

        // Process face detection results
        if (faces.isNotEmpty && imageSize.height > 0) {
          // Determine display height and effective size based on rotation
          final double displayHeight;
          final Size effectiveSize;
          if (_currentRotationDegrees == 90 || _currentRotationDegrees == 270) {
            displayHeight = imageSize.width; // camW is height in portrait
            effectiveSize = Size(imageSize.height, imageSize.width); // camH x camW (e.g. 720x1280)
          } else {
            displayHeight = imageSize.height; // camH is height in landscape
            effectiveSize = Size(imageSize.width, imageSize.height); // camW x camH (e.g. 1280x720)
          }

          // Count significant faces for orientation suggestion
          // A face is significant if it takes up at least 15% of frame height
          const significantThreshold = 15.0; // 15%

          for (final face in faces) {
            // With correct rotation, ML Kit height is always the vertical axis relative to display
            final faceHeight = face.boundingBox.height;
            if (displayHeight > 0) {
              final faceHeightPercentage = (faceHeight / displayHeight) * 100.0;
              if (faceHeightPercentage >= significantThreshold) {
                significantFaceCount++;
              }
            }
          }

          // Select best face for coaching and focus (handles multiple faces)
          // Uses a combination of size and position (larger + more central = better)
          Face? bestFace = _selectBestFace(faces, effectiveSize);
          
          if (bestFace != null) {
            // Calculate face height relative to the display vertical axis
            // With correct rotation, face.boundingBox.height is already vertical
            final faceHeight = bestFace.boundingBox.height;
            
            // Safety check: ensure valid face height
            if (faceHeight > 0 && displayHeight > 0) {
              final faceHeightPercentage = (faceHeight / displayHeight) * 100.0;
              
              // Evaluate distance coaching with hysteresis to prevent flickering
              coachingResult = evaluateDistanceCoaching(
                faceHeightPercentage,
                _currentDistanceScenario,
              );
              
              // Transform face center from camera coordinates to display coordinates
              // Now simplified because we pass the correct rotation to ML Kit!
              Offset displayFaceCenter;
              Size displayImageSize;

              // Camera image size (usually landscape: e.g. 1280x720)
              final camW = imageSize.width;
              final camH = imageSize.height;

              // Calculate face center in camera coordinates (as returned by ML Kit)
              // ML Kit returns coordinates in the rotated (upright) image space
              final rawFaceCenterX = bestFace.boundingBox.left + (bestFace.boundingBox.width / 2);
              final rawFaceCenterY = bestFace.boundingBox.top + (bestFace.boundingBox.height / 2);

              if (_currentRotationDegrees == 90 || _currentRotationDegrees == 270) {
                displayImageSize = Size(camH, camW);
              } else {
                displayImageSize = Size(camW, camH);
              }

              displayFaceCenter = Offset(rawFaceCenterX, rawFaceCenterY);

              // Mirror X for front camera to match mirrored preview
              if (_currentCamera?.lensDirection == CameraLensDirection.front) {
                displayFaceCenter = Offset(displayImageSize.width - displayFaceCenter.dx, displayFaceCenter.dy);
              }
              
              final normX = displayFaceCenter.dx / displayImageSize.width;
              final normY = displayFaceCenter.dy / displayImageSize.height;
              
              if (_frameCounter % 30 == 0) {
                final sO = _currentCamera?.sensorOrientation ?? 0;
                debugPrint('🔧 TRANSFORM: Sensor($sO) Raw(${rawFaceCenterX.toStringAsFixed(1)}, ${rawFaceCenterY.toStringAsFixed(1)}) on ${camW.toInt()}x${camH.toInt()} -> Display(${displayFaceCenter.dx.toStringAsFixed(1)}, ${displayFaceCenter.dy.toStringAsFixed(1)}) on ${displayImageSize.width.toInt()}x${displayImageSize.height.toInt()} | Norm[${normX.toStringAsFixed(3)}, ${normY.toStringAsFixed(3)}]');
              }

              // Now evaluate composition with display coordinates
              final compositionResult = evaluateComposition(
                displayFaceCenter,  // ✅ Transformed to display space!
                displayImageSize,   // ✅ Size matches display orientation!
                previousPowerPoint: _previousPowerPoint,
              );
              
              // Update composition guidance result and track power point for hysteresis
              if (mounted) {
                setState(() {
                  _compositionGuidanceResult = compositionResult;
                  _previousPowerPoint = compositionResult.nearestPowerPoint;
                  _lastDisplayFaceCenter = displayFaceCenter;
                  _lastDisplayImageSize = displayImageSize;
                });
              }
            }
          }
        } else {
          // No faces detected, clear previous state
          _previousFrameSample = null;
          _previousImageSize = null;
          // Clear composition guidance
          if (mounted) {
            setState(() {
              _compositionGuidanceResult = null;
              _previousPowerPoint = null;
              _lastDisplayFaceCenter = null;
            });
          }
        }
        
        // Always update UI when face detection runs
        if (mounted) {
          setState(() {
            _detectedFaces = faces;
            _imageSize = imageSize;
            _distanceCoachingResult = coachingResult;
            _currentDistanceScenario = coachingResult?.scenario;
            _significantFaceCount = significantFaceCount;
          });
        }
        
        // Debug composition guidance with transformed coordinates
        if (_frameCounter % 30 == 0 && faces.isNotEmpty && _compositionGuidanceResult != null) {
          debugPrint('COMPOSITION DEBUG: Face center ($_lastDisplayFaceCenter) | Size ($_lastDisplayImageSize) | Nearest PP: (${_compositionGuidanceResult!.nearestPowerPoint.x.toStringAsFixed(3)}, ${_compositionGuidanceResult!.nearestPowerPoint.y.toStringAsFixed(3)}) | Distance: ${_compositionGuidanceResult!.distancePercentage.toStringAsFixed(3)} | Status: ${_compositionGuidanceResult!.status}');
        }
        
        // Debug once only
        if (_frameCounter == 105 && faces.isNotEmpty) {
          final bestFace = _selectBestFace(faces, imageSize);
          final displayFace = bestFace ?? faces.first;
          debugPrint('');
          debugPrint('═══════════════════════════════════════════════════');
          debugPrint('SENSOR: ${_currentCamera?.sensorOrientation}° | IMAGE: ${image.width}x${image.height}');
          debugPrint('FACE BOUNDS (raw): ${displayFace.boundingBox}');
          debugPrint('NUMBER OF FACES: ${faces.length}');
          for (var i = 0; i < faces.length; i++) {
            debugPrint('FACE $i: ${faces[i].boundingBox}${bestFace == faces[i] ? " (BEST)" : ""}');
          }
          if (_distanceCoachingResult != null) {
            debugPrint('DISTANCE COACHING: ${_distanceCoachingResult!.scenario} - ${_distanceCoachingResult!.message} (${_distanceCoachingResult!.status})');
          }
          debugPrint('═══════════════════════════════════════════════════');
          debugPrint('');
        }
      }
    } catch (e) {
      // Don't spam console with repeated errors
      if (_frameCounter % 50 == 0) {
        debugPrint('Error processing image for face detection: $e');
      }
    } finally {
      _isProcessing = false;
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

  /// Handle tap to focus
  Future<void> _handleTapToFocus(TapDownDetails details, Size previewSize) async {
    if (_controller == null || !_controller!.value.isInitialized) {
      return;
    }
    
    try {
      // Calculate normalized position (0-1 range)
      final normalizedX = details.localPosition.dx / previewSize.width;
      final normalizedY = details.localPosition.dy / previewSize.height;
      
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
      
      await _controller!.setFocusPoint(focusPoint);
      
      // Show focus feedback ring
      setState(() {
        _focusPoint = details.localPosition;
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

  InputImage? _convertCameraImage(CameraImage image) {
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

    // Calculate rotation based on sensor orientation and device orientation
    _currentRotationDegrees = _calculateRotationDegrees();

    final InputImageRotation imageRotation =
        InputImageRotationValue.fromRawValue(_currentRotationDegrees) ??
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

  int _getIconRotationQuarterTurns() {
    switch (_deviceOrientation) {
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

  Future<void> _switchCamera() async {
    if (_cameras == null || _cameras!.length < 2 || _isProcessing) return;

    // Stop current stream before switching
    if (_controller != null && _controller!.value.isStreamingImages) {
      await _controller!.stopImageStream();
    }

    final lensDirection = _currentCamera?.lensDirection == CameraLensDirection.back
        ? CameraLensDirection.front
        : CameraLensDirection.back;

    final newCamera = _cameras!.firstWhere(
      (camera) => camera.lensDirection == lensDirection,
      orElse: () => _cameras!.first,
    );

    if (newCamera == _currentCamera) return;

    // Dispose old controller
    final oldController = _controller;
    _controller = null;
    if (mounted) setState(() {});
    await oldController?.dispose();

    _currentCamera = newCamera;
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
      _controller!.startImageStream(_processCameraImage);
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Error switching camera: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Ensure rotation is up to date for UI overlays
    _currentRotationDegrees = _calculateRotationDegrees();

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

    // Calculate the correct aspect ratio considering sensor orientation
    // Most phone cameras have sensors rotated 90 degrees
    final sensorOrientation = _currentCamera?.sensorOrientation ?? 0;
    final isLandscapeSensor = sensorOrientation == 90 || sensorOrientation == 270;
    
    double cameraAspectRatio;
    if (_imageSize != null) {
      // For landscape sensor orientations (90/270), swap width and height
      cameraAspectRatio = isLandscapeSensor 
          ? _imageSize!.height / _imageSize!.width 
          : _imageSize!.width / _imageSize!.height;
    } else {
      // Fallback to controller aspect ratio
      cameraAspectRatio = 1 / _controller!.value.aspectRatio;
    }
    
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera preview with face detection overlay - centered with correct aspect ratio
          Center(
            child: AspectRatio(
              aspectRatio: cameraAspectRatio,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final previewSize = Size(constraints.maxWidth, constraints.maxHeight);
                  
                  return GestureDetector(
                    onTapDown: (details) => _handleTapToFocus(details, previewSize),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CameraPreview(_controller!),
                        // Face detection overlay
                        CustomPaint(
                          painter: FaceDetectorPainter(
                            faces: _detectedFaces,
                            imageSize: _imageSize,
                            cameraPreviewSize: previewSize,
                            rotationDegrees: _currentRotationDegrees,
                            cameraLensDirection: _currentCamera?.lensDirection,
                          ),
                        ),
                        // Focus feedback ring
                        if (_focusPoint != null && _focusAnimationController != null)
                          AnimatedBuilder(
                            animation: _focusAnimation!,
                            builder: (context, child) {
                              return Positioned(
                                left: _focusPoint!.dx - 50,
                                top: _focusPoint!.dy - 50,
                                child: Container(
                                  width: 100,
                                  height: 100,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white.withValues(alpha: _focusAnimation!.value),
                                      width: 2,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        // Composition grid overlay (inside preview area)
                        CompositionGridOverlay(
                          compositionResult: _compositionGuidanceResult,
                          distanceResult: _distanceCoachingResult,
                          previewSize: previewSize,
                        ),
                      ],
                    ),
                  );
                },
              ),
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
          
          // Distance coaching overlay (rotates with orientation)
          DistanceCoachingOverlay(
            coachingResult: _distanceCoachingResult,
            compositionResult: _compositionGuidanceResult,
            significantFaceCount: _significantFaceCount,
            deviceOrientation: _deviceOrientation,
          ),
          
          // Bottom controls
          Positioned(
            bottom: _deviceOrientation == NativeDeviceOrientation.landscapeRight ? null : 0,
            top: _deviceOrientation == NativeDeviceOrientation.landscapeRight ? 0 : null,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: _deviceOrientation == NativeDeviceOrientation.landscapeRight 
                        ? Alignment.bottomCenter 
                        : Alignment.topCenter,
                    end: _deviceOrientation == NativeDeviceOrientation.landscapeRight 
                        ? Alignment.topCenter 
                        : Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.7),
                    ],
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: _deviceOrientation == NativeDeviceOrientation.landscapeRight
                      ? [
                          _buildThumbnailButton(),
                          _buildShutterButton(),
                          _buildCameraSwitchButton(),
                        ]
                      : [
                          _buildCameraSwitchButton(),
                          _buildShutterButton(),
                          _buildThumbnailButton(),
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
      child: Container(
        width: 70,
        height: 70,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.3),
            width: 4,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 10,
              spreadRadius: 2,
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
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
              ),
      ),
    );
  }

  Widget _buildCameraSwitchButton() {
    return GestureDetector(
      onTap: _switchCamera,
      child: RotatedBox(
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
  final CameraLensDirection? cameraLensDirection;

  static bool _hasLogged = false;

  FaceDetectorPainter({
    required this.faces,
    required this.imageSize,
    required this.cameraPreviewSize,
    required this.rotationDegrees,
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

      // Draw rectangle around the face
      canvas.drawRect(rect, paint);
    }
  }

  Rect _scaleRect({
    required Rect rect,
    required Size imageSize,
    required Size widgetSize,
  }) {
    // ML Kit returns coordinates in the rotated (upright) image space
    // We just need to scale them to the widget size, considering the rotated image dimensions.
    
    Size effectiveImageSize;
    if (rotationDegrees == 90 || rotationDegrees == 270) {
      effectiveImageSize = Size(imageSize.height, imageSize.width);
    } else {
      effectiveImageSize = Size(imageSize.width, imageSize.height);
    }

    final scaleX = widgetSize.width / effectiveImageSize.width;
    final scaleY = widgetSize.height / effectiveImageSize.height;

    double left = rect.left * scaleX;
    double top = rect.top * scaleY;
    double right = rect.right * scaleX;
    double bottom = rect.bottom * scaleY;

    // Handle mirroring for front camera
    if (cameraLensDirection == CameraLensDirection.front) {
      final mirroredLeft = widgetSize.width - right;
      final mirroredRight = widgetSize.width - left;
      left = mirroredLeft;
      right = mirroredRight;
    }

    return Rect.fromLTRB(left, top, right, bottom);
  }

  @override
  bool shouldRepaint(FaceDetectorPainter oldDelegate) => true;
}
