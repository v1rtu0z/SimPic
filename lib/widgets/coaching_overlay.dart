import 'package:flutter/material.dart';
import 'package:native_device_orientation/native_device_orientation.dart';
import '../models/distance_coaching_scenario.dart';
import '../models/composition_guidance.dart';
import '../models/orientation_guidance.dart';
import '../models/exposure_guidance.dart';
import '../models/blink_detection.dart';

/// Overlay widget for coaching UI
class CoachingOverlay extends StatelessWidget {
  final DistanceCoachingResult? coachingResult;
  final CompositionGuidanceResult? compositionResult;
  final FaceExposureResult? exposureResult;
  final BlinkDetectionResult? blinkResult;
  final int significantFaceCount;
  final NativeDeviceOrientation deviceOrientation;
  final bool isOrientationMismatch;

  const CoachingOverlay({
    super.key,
    this.coachingResult,
    this.compositionResult,
    this.exposureResult,
    this.blinkResult,
    this.significantFaceCount = 0,
    required this.deviceOrientation,
    this.isOrientationMismatch = false,
  });

  @override
  Widget build(BuildContext context) {
    final List<Widget> children = [];

    // 1. Orientation Suggestion Icon
    if (isOrientationMismatch) {
      final orientationGuidance = OrientationGuidance.evaluate(
        significantFaceCount: significantFaceCount,
        currentOrientation: deviceOrientation,
      );
      children.add(_buildOrientationSuggestion(orientationGuidance.suggestedOrientation));
    }

    // 1.1 Blink Status Icon
    if (blinkResult != null) {
      children.add(_buildBlinkIndicator());
    }

    // 2. Main Coaching Content
    if (!isOrientationMismatch) {
      final coachingData = _getCoachingData();
      if (coachingData != null) {
        // Determine orientation from physical device orientation
        final isLandscape = deviceOrientation == NativeDeviceOrientation.landscapeLeft ||
            deviceOrientation == NativeDeviceOrientation.landscapeRight;

        if (isLandscape) {
          final quarterTurns = deviceOrientation == NativeDeviceOrientation.landscapeLeft ? 1 : 3;
          children.add(Positioned(
            top: 0,
            left: 0,
            bottom: 0,
            width: 120, // Fixed width for vertical layout
            child: SafeArea(
              child: Center(
                child: RotatedBox(
                  quarterTurns: quarterTurns,
                  child: _buildOverlayContent(
                    coachingData.color,
                    coachingData.icon,
                    coachingData.message,
                  ),
                ),
              ),
            ),
          ));
        } else {
          children.add(Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: _buildOverlayContent(
                coachingData.color,
                coachingData.icon,
                coachingData.message,
              ),
            ),
          ));
        }
      }
    }

    if (children.isEmpty) {
      return const SizedBox.shrink();
    }

    return IgnorePointer(
      child: Stack(
        children: children,
      ),
    );
  }

  _CoachingData? _getCoachingData() {
    // If no coaching results, nothing to show
    if (coachingResult == null && compositionResult == null && exposureResult == null && (blinkResult == null || !blinkResult!.eitherEyeClosed)) return null;

    final List<String> messages = [];
    DistanceCoachingStatus distanceStatus = DistanceCoachingStatus.optimal;
    CompositionStatus compStatus = CompositionStatus.wellPositioned;
    ExposureStatus expStatus = ExposureStatus.good;

    if (coachingResult != null) {
      distanceStatus = coachingResult!.status;
      if (distanceStatus != DistanceCoachingStatus.optimal) {
        messages.add(coachingResult!.message);
      }
    }

    if (exposureResult != null) {
      expStatus = exposureResult!.status;
      if (expStatus != ExposureStatus.good && exposureResult!.message.isNotEmpty) {
        messages.add(exposureResult!.message);
      }
    }

    if (blinkResult != null && blinkResult!.eitherEyeClosed) {
      messages.add(blinkResult!.message);
    }

    if (compositionResult != null) {
      // In landscape and multi-face mode, composition coaching is logically disabled
      final bool isLandscape = deviceOrientation == NativeDeviceOrientation.landscapeLeft ||
          deviceOrientation == NativeDeviceOrientation.landscapeRight;
      final bool isMultiFaceGroup = significantFaceCount >= 2;
      
      if (!(isLandscape && isMultiFaceGroup)) {
        compStatus = compositionResult!.status;
        if (compStatus != CompositionStatus.wellPositioned) {
          if (messages.isEmpty) {
            messages.add('Adjust positioning');
          }
        }
      }
    }

    // If both are good, show "Good framing" or similar
    if (messages.isEmpty) {
      if (coachingResult != null && compositionResult != null) {
        return const _CoachingData(
          message: 'Perfect framing',
          color: Colors.green,
          icon: Icons.check_circle,
        );
      } else if (coachingResult != null) {
        return _CoachingData(
          message: coachingResult!.message,
          color: Colors.green,
          icon: Icons.check_circle,
        );
      } else if (compositionResult != null) {
        return const _CoachingData(
          message: 'Good positioning',
          color: Colors.green,
          icon: Icons.check_circle,
        );
      } else if (blinkResult != null && !blinkResult!.eitherEyeClosed) {
        return const _CoachingData(
          message: 'Eyes open',
          color: Colors.green,
          icon: Icons.remove_red_eye,
        );
      }
      return null;
    }

    // If we have messages, it means something is not optimal
    final String combinedMessage = messages.isNotEmpty ? messages.join(' & ') : "✓ Good lighting";
    
    // Priority for color: Red (critical issues) > Orange (warnings) > Green (Good)
    Color statusColor = Colors.green;
    IconData statusIcon = Icons.check_circle_outline;

    if (expStatus == ExposureStatus.backlit || 
        expStatus == ExposureStatus.shadowed ||
        distanceStatus == DistanceCoachingStatus.tooClose ||
        (blinkResult != null && blinkResult!.eitherEyeClosed)) {
      statusColor = Colors.red;
      statusIcon = Icons.warning_amber_rounded;
      
      if (blinkResult != null && blinkResult!.eitherEyeClosed) {
        statusIcon = Icons.remove_red_eye_outlined;
      } else if (expStatus == ExposureStatus.backlit) {
        statusIcon = Icons.wb_sunny_rounded;
      } else if (expStatus == ExposureStatus.shadowed) {
        statusIcon = Icons.exposure_rounded;
      } else if (distanceStatus == DistanceCoachingStatus.tooClose) {
        statusIcon = Icons.arrow_downward;
      }
    } else if (distanceStatus == DistanceCoachingStatus.tooFar || 
               compStatus == CompositionStatus.needsAdjustment ||
               expStatus == ExposureStatus.underexposed) {
      statusColor = Colors.orange;
      statusIcon = Icons.info_outline;

      if (distanceStatus == DistanceCoachingStatus.tooFar) {
        statusIcon = Icons.arrow_upward;
      } else if (compStatus == CompositionStatus.needsAdjustment) {
        statusIcon = Icons.grid_view;
      } else if (expStatus == ExposureStatus.underexposed) {
        statusIcon = Icons.nightlight_round;
      }
    }

    return _CoachingData(
      color: statusColor,
      icon: statusIcon,
      message: combinedMessage,
    );
  }

  Widget _buildOrientationSuggestion(OrientationSuggestion suggestion) {
    final isLandscape = deviceOrientation == NativeDeviceOrientation.landscapeLeft ||
        deviceOrientation == NativeDeviceOrientation.landscapeRight;
        
    if (isLandscape) {
      final quarterTurns = deviceOrientation == NativeDeviceOrientation.landscapeLeft ? 1 : 3;
      return Positioned(
        top: 20,
        right: 20,
        child: SafeArea(
          child: RotatedBox(
            quarterTurns: quarterTurns,
            child: _buildOrientationIcon(suggestion),
          ),
        ),
      );
    } else {
      return Positioned(
        top: 80, // Lowered to avoid overlap with coaching text
        right: 20,
        child: SafeArea(
          child: _buildOrientationIcon(suggestion),
        ),
      );
    }
  }

  Widget _buildOrientationIcon(OrientationSuggestion suggestion) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.orangeAccent.withValues(alpha: 0.6),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.screen_rotation,
            color: Colors.orangeAccent,
            size: 32,
          ),
          const SizedBox(height: 4),
          Text(
            suggestion == OrientationSuggestion.portrait ? 'FLIP TO PORTRAIT' : 'FLIP TO LANDSCAPE',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBlinkIndicator() {
    final bool isLandscape = deviceOrientation == NativeDeviceOrientation.landscapeLeft ||
        deviceOrientation == NativeDeviceOrientation.landscapeRight;
    
    final bool eyesClosed = blinkResult!.eitherEyeClosed;
    final Color color = eyesClosed ? Colors.red : Colors.green;
    final IconData icon = eyesClosed ? Icons.remove_red_eye_outlined : Icons.remove_red_eye;
    
    Widget content = Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.5), width: 2),
      ),
      child: Icon(icon, color: color, size: 24),
    );

    if (isLandscape) {
      final quarterTurns = deviceOrientation == NativeDeviceOrientation.landscapeLeft ? 1 : 3;
      return Positioned(
        top: 20,
        left: 20,
        child: SafeArea(
          child: RotatedBox(
            quarterTurns: quarterTurns,
            child: content,
          ),
        ),
      );
    } else {
      return Positioned(
        top: 80,
        left: 20,
        child: SafeArea(
          child: content,
        ),
      );
    }
  }

  Widget _buildOverlayContent(Color statusColor, IconData statusIcon, String message) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: statusColor.withValues(alpha: 0.4),
          width: 2,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            statusIcon,
            color: statusColor,
            size: 28,
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CoachingData {
  final String message;
  final Color color;
  final IconData icon;

  const _CoachingData({
    required this.message,
    required this.color,
    required this.icon,
  });
}
