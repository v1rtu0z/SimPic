import 'dart:async';
import 'package:flutter/material.dart';
import 'package:native_device_orientation/native_device_orientation.dart';
import '../models/distance_coaching_scenario.dart';

/// Overlay widget for distance coaching UI
class DistanceCoachingOverlay extends StatefulWidget {
  final DistanceCoachingResult? coachingResult;

  const DistanceCoachingOverlay({
    super.key,
    this.coachingResult,
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
    // Hide overlay if no coaching result (no face detected)
    if (widget.coachingResult == null) {
      return const SizedBox.shrink();
    }

    final status = widget.coachingResult!.status;
    final message = widget.coachingResult!.message;
    final scenario = widget.coachingResult!.scenario;

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
    
    // Position based on physical device orientation
    if (isLandscape) {
      // In landscape, position on the left side with vertical text
      // landscapeLeft needs 90° counter-clockwise (quarterTurns: 1)
      // landscapeRight needs 270° counter-clockwise (quarterTurns: 3) to keep text readable
      final quarterTurns = _deviceOrientation == NativeDeviceOrientation.landscapeLeft ? 1 : 3;
      
      return Positioned(
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
      );
    } else {
      // FIXME: Flipped portrait mode (portraitDown) - overlay positioning and rotation not handled
      // Currently treats all portrait orientations the same, but portraitDown may need different positioning/rotation
      // In portrait, position at the top
      return Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: SafeArea(
          child: _buildOverlayContent(statusColor, statusIcon, message, scenario),
        ),
      );
    }
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
