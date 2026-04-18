import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// Portrait detection result with confidence score and debug information
class PortraitAnalysisResult {
  final bool isPortraitCandidate;
  final double confidenceScore; // 0.0 to 1.0
  final bool isActive; // True when portrait mode should be active
  final PortraitDebugInfo debugInfo;

  const PortraitAnalysisResult({
    required this.isPortraitCandidate,
    required this.confidenceScore,
    required this.isActive,
    required this.debugInfo,
  });
}

/// Debug information for portrait detection
class PortraitDebugInfo {
  final double faceSizeRatio; // Face height as percentage of frame height
  final double distanceFromCenter; // Normalized distance (0.0 = center, 1.0 = edge)
  final double stabilityFactor; // Movement delta normalized to threshold (0.0 = stable, 1.0+ = moving)
  final double? actualMovementPercent; // Actual movement as percentage of frame (for display)
  final int consecutiveFrameCount; // Frames with confidence >= threshold
  final bool isHardwareExtensionAvailable; // CameraX bokeh extension available
  final String? failureReason; // Why portrait mode isn't active
  final bool? isWellComposed; // Whether face follows composition coaching (null = not checked)

  const PortraitDebugInfo({
    required this.faceSizeRatio,
    required this.distanceFromCenter,
    required this.stabilityFactor,
    required this.consecutiveFrameCount,
    required this.isHardwareExtensionAvailable,
    this.failureReason,
    this.actualMovementPercent,
    this.isWellComposed,
  });
}

/// Portrait detection thresholds
class PortraitThresholds {
  // Face size: between 20% and 55% of frame height
  static const double minFaceSizeRatio = 0.20;
  static const double maxFaceSizeRatio = 0.55;

  // Face must be within central 60% of frame
  static const double maxDistanceFromCenter = 0.30; // 30% from center = 60% central zone

  // Stability: movement delta threshold (normalized to frame size)
  // Increased to 15% to account for natural hand shake - users can't hold phone perfectly still
  static const double maxMovementDelta = 0.15; // 15% of frame size (was 5%, too sensitive)

  // Activation: 15 consecutive frames at 100% confidence
  static const int activationFrameCount = 15;

  // Deactivation: 20 consecutive frames below 50% confidence
  static const int deactivationFrameCount = 20;
  static const double deactivationConfidenceThreshold = 0.50;
}

/// Portrait detection state tracker
class PortraitDetectionState {
  int _consecutiveHighConfidenceFrames = 0;
  int _consecutiveLowConfidenceFrames = 0;
  bool _isActive = false;
  Offset? _lastFaceCenter;
  DateTime? _lastStableTime;
  double _currentMovementDelta = 0.0; // Track current movement for debugging
  static const Duration stabilityDuration = Duration(milliseconds: 500);

  bool get isActive => _isActive;
  double get currentMovementDelta => _currentMovementDelta;

  /// Update state based on new confidence score
  PortraitAnalysisResult update(
    double confidenceScore,
    PortraitDebugInfo debugInfo,
  ) {
    if (confidenceScore >= 1.0) {
      // Perfect confidence - increment activation counter
      _consecutiveHighConfidenceFrames++;
      _consecutiveLowConfidenceFrames = 0;

      // Check if we should activate
      if (!_isActive && _consecutiveHighConfidenceFrames >= PortraitThresholds.activationFrameCount) {
        _isActive = true;
        debugPrint('[AUTO_PORTRAIT] ✅ ACTIVATED after $_consecutiveHighConfidenceFrames frames');
      }
    } else if (confidenceScore < PortraitThresholds.deactivationConfidenceThreshold) {
      // Low confidence - increment deactivation counter
      _consecutiveLowConfidenceFrames++;
      _consecutiveHighConfidenceFrames = 0;

      // Check if we should deactivate
      if (_isActive && _consecutiveLowConfidenceFrames >= PortraitThresholds.deactivationFrameCount) {
        _isActive = false;
        debugPrint('[AUTO_PORTRAIT] ❌ DEACTIVATED after $_consecutiveLowConfidenceFrames frames');
      }
    } else {
      // Medium confidence - reset both counters
      _consecutiveHighConfidenceFrames = 0;
      _consecutiveLowConfidenceFrames = 0;
    }

    return PortraitAnalysisResult(
      isPortraitCandidate: confidenceScore > 0.5,
      confidenceScore: confidenceScore,
      isActive: _isActive,
      debugInfo: debugInfo.copyWith(
        consecutiveFrameCount: _isActive 
            ? _consecutiveLowConfidenceFrames 
            : _consecutiveHighConfidenceFrames,
      ),
    );
  }

  /// Reset state (e.g., when face is lost)
  void reset() {
    if (_isActive) {
      debugPrint('[AUTO_PORTRAIT] 🔄 RESET (face lost)');
    }
    _isActive = false;
    _consecutiveHighConfidenceFrames = 0;
    _consecutiveLowConfidenceFrames = 0;
    _lastFaceCenter = null;
    _lastStableTime = null;
    _currentMovementDelta = 0.0;
  }

  /// Update face center for stability tracking
  /// frameSize is used to normalize movement delta (0.0 to 1.0)
  void updateFaceCenter(Offset? faceCenter, Size frameSize) {
    if (faceCenter == null) {
      _lastFaceCenter = null;
      _lastStableTime = null;
      _currentMovementDelta = 1.0; // Max movement when no face
      return;
    }

    if (_lastFaceCenter != null) {
      // Calculate absolute pixel movement
      final pixelDelta = (faceCenter - _lastFaceCenter!).distance;
      // Normalize to frame size (use minimum dimension for consistency)
      final frameMinDimension = min(frameSize.width, frameSize.height);
      final normalizedDelta = frameMinDimension > 0 ? pixelDelta / frameMinDimension : 0.0;
      _currentMovementDelta = normalizedDelta;
      
      // Consider stable if movement is below threshold
      if (normalizedDelta < PortraitThresholds.maxMovementDelta) {
        _lastStableTime ??= DateTime.now();
      } else {
        // Movement exceeded threshold - reset stability timer
        _lastStableTime = null;
      }
    } else {
      // First frame - no previous position, so no movement yet
      _currentMovementDelta = 0.0;
      // Don't set _lastStableTime yet - need at least 2 frames to determine stability
    }

    _lastFaceCenter = faceCenter;
  }

  /// Check if face has been stable for required duration
  bool get isStable {
    if (_lastStableTime == null) return false;
    return DateTime.now().difference(_lastStableTime!) >= stabilityDuration;
  }
}

/// Extension to add copyWith to PortraitDebugInfo
extension PortraitDebugInfoExtension on PortraitDebugInfo {
  PortraitDebugInfo copyWith({
    double? faceSizeRatio,
    double? distanceFromCenter,
    double? stabilityFactor,
    int? consecutiveFrameCount,
    bool? isHardwareExtensionAvailable,
    String? failureReason,
    double? actualMovementPercent,
    bool? isWellComposed,
  }) {
    return PortraitDebugInfo(
      faceSizeRatio: faceSizeRatio ?? this.faceSizeRatio,
      distanceFromCenter: distanceFromCenter ?? this.distanceFromCenter,
      stabilityFactor: stabilityFactor ?? this.stabilityFactor,
      consecutiveFrameCount: consecutiveFrameCount ?? this.consecutiveFrameCount,
      isHardwareExtensionAvailable: isHardwareExtensionAvailable ?? this.isHardwareExtensionAvailable,
      failureReason: failureReason ?? this.failureReason,
      actualMovementPercent: actualMovementPercent ?? this.actualMovementPercent,
      isWellComposed: isWellComposed ?? this.isWellComposed,
    );
  }
}

/// Analyze if current frame is a portrait candidate
PortraitAnalysisResult analyzePortraitCandidate({
  required List<Face> faces,
  required Size imageSize, // Raw camera image size
  required Size displayImageSize, // Display-aligned image size (accounts for rotation)
  required Offset? faceCenter, // Face center in display coordinates
  required PortraitDetectionState state,
  bool isHardwareExtensionAvailable = false,
  int frameCounter = 0,
  bool isFrontCamera = false, // For adjusting thresholds for selfies
  bool isWellComposed = false, // Whether face follows composition coaching (rule of thirds)
}) {
  // Update face center for stability tracking (use display size for consistency)
  state.updateFaceCenter(faceCenter, displayImageSize);

  // Create debug info
  final debugInfo = PortraitDebugInfo(
    faceSizeRatio: 0.0,
    distanceFromCenter: 1.0,
    stabilityFactor: 1.0,
    consecutiveFrameCount: 0,
    isHardwareExtensionAvailable: isHardwareExtensionAvailable,
    failureReason: null,
    actualMovementPercent: null,
  );

  // Check 1: Exactly 1 significant face
  if (faces.isEmpty) {
    state.reset();
    if (frameCounter % 30 == 0) {
      debugPrint('[AUTO_PORTRAIT_DEBUG] No faces detected');
    }
    return PortraitAnalysisResult(
      isPortraitCandidate: false,
      confidenceScore: 0.0,
      isActive: false,
      debugInfo: debugInfo.copyWith(failureReason: 'No faces detected'),
    );
  }

  if (faces.length > 1) {
    state.reset();
    if (frameCounter % 30 == 0) {
      debugPrint('[AUTO_PORTRAIT_DEBUG] Multiple faces detected (${faces.length})');
    }
    return PortraitAnalysisResult(
      isPortraitCandidate: false,
      confidenceScore: 0.0,
      isActive: false,
      debugInfo: debugInfo.copyWith(failureReason: 'Multiple faces (${faces.length})'),
    );
  }

  final face = faces.first;
  final faceHeight = face.boundingBox.height;
  // Use display height for face size calculation (accounts for rotation)
  final frameHeight = displayImageSize.height;
  final faceSizeRatio = faceHeight / frameHeight;
  
  // Adjust max face size for front camera (selfies naturally have larger faces)
  final maxFaceSizeRatio = isFrontCamera 
      ? PortraitThresholds.maxFaceSizeRatio * 1.2 // 20% more lenient for selfies (66% max)
      : PortraitThresholds.maxFaceSizeRatio;

  // Check 2: Face size between 20% and max% of frame height (adjusted for front camera)
  bool faceSizeValid = faceSizeRatio >= PortraitThresholds.minFaceSizeRatio &&
      faceSizeRatio <= maxFaceSizeRatio;

  if (!faceSizeValid) {
    state.reset();
    if (frameCounter % 30 == 0) {
      debugPrint('[AUTO_PORTRAIT_DEBUG] Face size out of range: ${(faceSizeRatio * 100).toStringAsFixed(1)}% (required: ${(PortraitThresholds.minFaceSizeRatio * 100).toStringAsFixed(0)}%-${(maxFaceSizeRatio * 100).toStringAsFixed(0)}%${isFrontCamera ? " [selfie adjusted]" : ""})');
    }
    return PortraitAnalysisResult(
      isPortraitCandidate: false,
      confidenceScore: 0.0,
      isActive: false,
      debugInfo: debugInfo.copyWith(
        faceSizeRatio: faceSizeRatio,
        failureReason: 'Face size ${(faceSizeRatio * 100).toStringAsFixed(1)}% out of range (${(PortraitThresholds.minFaceSizeRatio * 100).toStringAsFixed(0)}%-${(maxFaceSizeRatio * 100).toStringAsFixed(0)}%${isFrontCamera ? " [selfie]" : ""})',
      ),
    );
  }

  // Check 3: Face center within central 60% of frame
  if (faceCenter == null) {
    state.reset();
    if (frameCounter % 30 == 0) {
      debugPrint('[AUTO_PORTRAIT_DEBUG] Face center not available');
    }
    return PortraitAnalysisResult(
      isPortraitCandidate: false,
      confidenceScore: 0.0,
      isActive: false,
      debugInfo: debugInfo.copyWith(
        faceSizeRatio: faceSizeRatio,
        failureReason: 'Face center not available',
      ),
    );
  }

  // Use display coordinates for center calculation (faceCenter is in display space)
  final displayCenter = Offset(displayImageSize.width / 2, displayImageSize.height / 2);
  final distanceFromCenter = (faceCenter - displayCenter).distance;
  final maxDistance = min(displayImageSize.width, displayImageSize.height) * PortraitThresholds.maxDistanceFromCenter;
  final normalizedDistance = maxDistance > 0 ? distanceFromCenter / maxDistance : 1.0;
  
  // Accept position if either:
  // 1. Face is within central zone (traditional portrait requirement), OR
  // 2. Face follows good composition (rule of thirds) - allows artistic portraits
  final isCentered = normalizedDistance <= 1.0;
  final positionValid = isCentered || isWellComposed;
  
  // Log coordinate info for debugging
  if (frameCounter % 30 == 0) {
    debugPrint('[AUTO_PORTRAIT_DEBUG] Position check: faceCenter=$faceCenter, displayCenter=$displayCenter, '
        'displaySize=$displayImageSize, distance=$distanceFromCenter, maxDistance=$maxDistance, '
        'normalized=${(normalizedDistance * 100).toStringAsFixed(1)}%, '
        'isCentered=$isCentered, isWellComposed=$isWellComposed, positionValid=$positionValid');
  }

  if (!positionValid) {
    state.reset();
    if (frameCounter % 30 == 0) {
      debugPrint('[AUTO_PORTRAIT_DEBUG] Face position invalid: center distance ${(normalizedDistance * 100).toStringAsFixed(1)}% (max: ${(PortraitThresholds.maxDistanceFromCenter * 100).toStringAsFixed(0)}%), well-composed: $isWellComposed');
    }
    return PortraitAnalysisResult(
      isPortraitCandidate: false,
      confidenceScore: 0.0,
      isActive: false,
      debugInfo: debugInfo.copyWith(
        faceSizeRatio: faceSizeRatio,
        distanceFromCenter: normalizedDistance,
        isWellComposed: isWellComposed,
        failureReason: isWellComposed 
            ? 'Face position invalid (center: ${(normalizedDistance * 100).toStringAsFixed(1)}%)'
            : 'Face too far from center: ${(normalizedDistance * 100).toStringAsFixed(1)}% (max: ${(PortraitThresholds.maxDistanceFromCenter * 100).toStringAsFixed(0)}%) or not well-composed',
      ),
    );
  }

  // Check 4: Stability (face movement)
  // Calculate stability factor based on actual movement amount (0.0 = stable, 1.0 = moving a lot)
  // Normalize movement delta to threshold for display
  final movementDelta = state.currentMovementDelta;
  // If movementDelta is 0, we're either perfectly still or it's the first frame
  // For first frame, show 0% movement. For subsequent frames, calculate factor.
  final stabilityFactor = movementDelta > 0 
      ? min(1.0, movementDelta / PortraitThresholds.maxMovementDelta) 
      : 0.0; // First frame or perfectly still

  // Calculate confidence score (0.0 to 1.0)
  // All criteria met = 1.0, partial = 0.0-1.0
  double confidenceScore = 1.0;

  // Reduce confidence if not stable
  if (!state.isStable) {
    confidenceScore *= 0.7; // 70% confidence if not stable yet
  }

  // Reduce confidence based on distance from center (closer to center = higher confidence)
  confidenceScore *= (1.0 - normalizedDistance * 0.3); // Up to 30% reduction

  // Reduce confidence if face size is near boundaries
  final sizeFromMin = (faceSizeRatio - PortraitThresholds.minFaceSizeRatio) / 
      (PortraitThresholds.maxFaceSizeRatio - PortraitThresholds.minFaceSizeRatio);
  if (sizeFromMin < 0.1 || sizeFromMin > 0.9) {
    confidenceScore *= 0.8; // 20% reduction if near boundaries
  }

  confidenceScore = confidenceScore.clamp(0.0, 1.0);

  // Calculate actual movement percentage (always available - 0.0 on first frame, actual value after)
  final actualMovementPercent = movementDelta * 100; // Always calculate, even if 0.0

  // Log debug info every 30 frames
  if (frameCounter % 30 == 0) {
    debugPrint('[AUTO_PORTRAIT_DEBUG] Face size: ${(faceSizeRatio * 100).toStringAsFixed(1)}% (range: ${(PortraitThresholds.minFaceSizeRatio * 100).toStringAsFixed(0)}%-${(PortraitThresholds.maxFaceSizeRatio * 100).toStringAsFixed(0)}%), '
        'Distance from center: ${(normalizedDistance * 100).toStringAsFixed(1)}% (max: ${(PortraitThresholds.maxDistanceFromCenter * 100).toStringAsFixed(0)}%), '
        'Movement: ${actualMovementPercent.toStringAsFixed(2)}% (threshold: ${(PortraitThresholds.maxMovementDelta * 100).toStringAsFixed(0)}%), '
        'Stable: ${state.isStable} (${state.isStable ? "✓" : "✗"}), '
        'Confidence: ${(confidenceScore * 100).toStringAsFixed(1)}%');
  }

  // Update state and return result
  
  final updatedDebugInfo = debugInfo.copyWith(
    faceSizeRatio: faceSizeRatio,
    distanceFromCenter: normalizedDistance,
    stabilityFactor: stabilityFactor,
    actualMovementPercent: actualMovementPercent, // Store actual movement as percentage
    isWellComposed: isWellComposed,
  );

  return state.update(confidenceScore, updatedDebugInfo);
}
