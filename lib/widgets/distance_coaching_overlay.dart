import 'dart:async';
import 'package:flutter/material.dart';
import 'package:native_device_orientation/native_device_orientation.dart';
import '../models/distance_coaching_scenario.dart';
import '../models/composition_guidance.dart';
import '../models/orientation_guidance.dart';

/// Overlay widget for distance coaching UI
class DistanceCoachingOverlay extends StatefulWidget {
  final DistanceCoachingResult? coachingResult;
  final CompositionGuidanceResult? compositionResult;
  final int significantFaceCount;

  const DistanceCoachingOverlay({
    super.key,
    this.coachingResult,
    this.compositionResult,
    this.significantFaceCount = 0,
  });

  @override
  State<DistanceCoachingOverlay> createState() => _DistanceCoachingOverlayState();
}

class _DistanceCoachingOverlayState extends State<DistanceCoachingOverlay> {
  NativeDeviceOrientation _deviceOrientation = NativeDeviceOrientation.portraitUp;
  StreamSubscription<NativeDeviceOrientation>? _orientationSubscription;

  @override
  void initState() {
    super.initState();
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
  }

  @override
  void dispose() {
    _orientationSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final orientationGuidance = OrientationGuidance.evaluate(
      significantFaceCount: widget.significantFaceCount,
      currentOrientation: _deviceOrientation,
    );

    final List<Widget> children = [];

    // 1. Orientation Suggestion Icon
    if (orientationGuidance.isMismatch) {
      children.add(_buildOrientationSuggestion(orientationGuidance.suggestedOrientation));
    }

    // 2. Distance Coaching Content
    if (widget.coachingResult != null) {
      final status = widget.coachingResult!.status;
      String message = widget.coachingResult!.message;
      final scenario = widget.coachingResult!.scenario;
      
      // If distance is optimal and composition is also optimal, append positioning info
      if (status == DistanceCoachingStatus.optimal && 
          widget.compositionResult != null &&
          widget.compositionResult!.status == CompositionStatus.wellPositioned) {
        message = '$message, positioning';
      }

      // Determine color based on status
      Color statusColor;
      IconData statusIcon;
      
      switch (status) {
        case DistanceCoachingStatus.optimal:
          statusColor = Colors.green;
          statusIcon = Icons.check_circle;
          break;
        case DistanceCoachingStatus.tooClose:
          statusColor = Colors.red;
          statusIcon = Icons.arrow_downward;
          break;
        case DistanceCoachingStatus.tooFar:
          statusColor = Colors.orange;
          statusIcon = Icons.arrow_upward;
          break;
      }

      // Determine orientation from physical device orientation
      final isLandscape = _deviceOrientation == NativeDeviceOrientation.landscapeLeft ||
          _deviceOrientation == NativeDeviceOrientation.landscapeRight;
      
      if (isLandscape) {
        final quarterTurns = _deviceOrientation == NativeDeviceOrientation.landscapeLeft ? 1 : 3;
        children.add(Positioned(
          top: 0,
          left: 0,
          bottom: 0,
          width: 120, // Fixed width for vertical layout
          child: SafeArea(
            child: Center(
              child: RotatedBox(
                quarterTurns: quarterTurns,
                child: _buildOverlayContent(statusColor, statusIcon, message, scenario),
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
            child: _buildOverlayContent(statusColor, statusIcon, message, scenario),
          ),
        ));
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

  Widget _buildOrientationSuggestion(OrientationSuggestion suggestion) {
    final isLandscape = _deviceOrientation == NativeDeviceOrientation.landscapeLeft ||
        _deviceOrientation == NativeDeviceOrientation.landscapeRight;
        
    if (isLandscape) {
      final quarterTurns = _deviceOrientation == NativeDeviceOrientation.landscapeLeft ? 1 : 3;
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
        top: 80, // Lowered to avoid overlap with distance coaching text
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

  Widget _buildOverlayContent(Color statusColor, IconData statusIcon, String message, DistanceCoachingScenario scenario) {
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
                  message,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _getScenarioLabel(scenario),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 12,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getScenarioLabel(DistanceCoachingScenario scenario) {
    switch (scenario) {
      case DistanceCoachingScenario.closeUpPortrait:
        return 'Close-up portrait';
      case DistanceCoachingScenario.waistUp:
        return 'Waist-up portrait';
      case DistanceCoachingScenario.fullBody:
        return 'Full body';
    }
  }
}
