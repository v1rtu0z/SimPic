import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
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

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
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
    
    _initializeCamera();
    _loadLatestPhoto();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    _flashAnimationController.dispose();
    _minimizeAnimationController.dispose();
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
      final backCamera = _cameras!.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras!.first,
      );

      // Initialize camera controller
      _controller = CameraController(
        backCamera,
        ResolutionPreset.high,
        enableAudio: false,
      );

      await _controller!.initialize();

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
      setState(() {
        _isCapturing = false;
      });
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

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera preview
          Positioned.fill(
            child: CameraPreview(_controller!),
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
                    // Image preview thumbnail
                    GestureDetector(
                      onTap: () {
                        if (_lastImageFile != null) {
                          _showImagePreview(_lastImageFile!);
                        }
                      },
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
                    
                    // Shutter button
                    GestureDetector(
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
                    ),
                    
                    // Placeholder for symmetry (or future button)
                    const SizedBox(width: 60),
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
