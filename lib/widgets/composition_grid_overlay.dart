import 'dart:async';
import 'package:flutter/material.dart';
import 'package:native_device_orientation/native_device_orientation.dart';
import '../models/composition_guidance.dart';
import '../models/distance_coaching_scenario.dart';

/// Overlay widget for composition grid and face positioning guidance
class CompositionGridOverlay extends StatefulWidget {
  final CompositionGuidanceResult? compositionResult;
  final DistanceCoachingResult? distanceResult; // Used to determine if we should show active guidance
  final Size? previewSize;

  const CompositionGridOverlay({
    super.key,
    this.compositionResult,
    this.distanceResult,
    this.previewSize,
  });

  @override
  State<CompositionGridOverlay> createState() => _CompositionGridOverlayState();
}

class _CompositionGridOverlayState extends State<CompositionGridOverlay>
    with SingleTickerProviderStateMixin {
  NativeDeviceOrientation _deviceOrientation = NativeDeviceOrientation.portraitUp;
  StreamSubscription<NativeDeviceOrientation>? _orientationSubscription;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    
    // Listen to device orientation
    _orientationSubscription = NativeDeviceOrientationCommunicator()
        .onOrientationChanged(useSensor: true)
        .listen((orientation) {
      if (mounted) {
        setState(() {
          _deviceOrientation = orientation;
        });
      }
    });
    
    // Pulse animation for power points
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _orientationSubscription?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  /// Check if distance is optimal (allows composition guidance to be active)
  bool get _isDistanceOptimal {
    return widget.distanceResult?.status == DistanceCoachingStatus.optimal;
  }

  @override
  Widget build(BuildContext context) {
    // Always show grid (subtle), but only show active guidance when distance is optimal
    if (widget.previewSize == null) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      width: widget.previewSize!.width,
      height: widget.previewSize!.height,
      child: CustomPaint(
        painter: CompositionGridPainter(
          compositionResult: widget.compositionResult,
          isDistanceOptimal: _isDistanceOptimal,
          pulseAnimation: _pulseAnimation,
        ),
      ),
    );
  }
}

/// Custom painter for composition grid overlay
class CompositionGridPainter extends CustomPainter {
  final CompositionGuidanceResult? compositionResult;
  final bool isDistanceOptimal;
  final Animation<double> pulseAnimation;

  CompositionGridPainter({
    required this.compositionResult,
    required this.isDistanceOptimal,
    required this.pulseAnimation,
  }) : super(repaint: pulseAnimation);

  @override
  void paint(Canvas canvas, Size size) {
    // Calculate power points in screen coordinates
    final powerPoints = _calculatePowerPoints(size);
    
    // Draw grid lines (always visible, subtle)
    _drawGridLines(canvas, size);
    
    // Draw power points
    _drawPowerPoints(canvas, size, powerPoints);
    
    // Draw directional arrows (only when distance is optimal AND needs adjustment)
    if (isDistanceOptimal && 
        compositionResult != null && 
        compositionResult!.status == CompositionStatus.needsAdjustment) {
      _drawDirectionalArrows(canvas, size, compositionResult!);
    }
  }

  /// Calculate power points in screen coordinates
  List<Offset> _calculatePowerPoints(Size size) {
    const third = 1.0 / 3.0;
    const twoThirds = 2.0 / 3.0;
    
    return [
      Offset(size.width * third, size.height * third),
      Offset(size.width * twoThirds, size.height * third),
      Offset(size.width * third, size.height * twoThirds),
      Offset(size.width * twoThirds, size.height * twoThirds),
    ];
  }

  /// Draw rule of thirds grid lines
  void _drawGridLines(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.35) // More pronounced
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    const third = 1.0 / 3.0;
    const twoThirds = 2.0 / 3.0;

    // Vertical lines
    canvas.drawLine(
      Offset(size.width * third, 0),
      Offset(size.width * third, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(size.width * twoThirds, 0),
      Offset(size.width * twoThirds, size.height),
      paint,
    );

    // Horizontal lines
    canvas.drawLine(
      Offset(0, size.height * third),
      Offset(size.width, size.height * third),
      paint,
    );
    canvas.drawLine(
      Offset(0, size.height * twoThirds),
      Offset(size.width, size.height * twoThirds),
      paint,
    );
  }

  /// Draw power points (circles at intersections)
  void _drawPowerPoints(Canvas canvas, Size size, List<Offset> powerPoints) {
    if (compositionResult == null) {
      // No face detected - show all power points as static
      final paint = Paint()
        ..color = Colors.white.withValues(alpha: 0.25)
        ..style = PaintingStyle.fill;
      
      for (final point in powerPoints) {
        canvas.drawCircle(point, 8, paint);
      }
      return;
    }

    // Get the target power point from composition result
    final targetNormalized = compositionResult!.nearestPowerPoint;
    
    // Draw all power points
    for (final point in powerPoints) {
      // Calculate normalized coordinates for this power point
      final pointNormalizedX = point.dx / size.width;
      final pointNormalizedY = point.dy / size.height;
      
      // Match power point by comparing normalized coordinates
      // Use tolerance to account for floating point precision
      const tolerance = 0.005; // Small tolerance for floating point comparison
      final isTarget = (pointNormalizedX - targetNormalized.x).abs() < tolerance &&
                       (pointNormalizedY - targetNormalized.y).abs() < tolerance;
      
      // Only highlight target power point when distance is optimal AND composition needs adjustment
      if (isTarget && 
          isDistanceOptimal && 
          compositionResult!.status == CompositionStatus.needsAdjustment) {
        // Target power point: pulsing and highlighted
        final pulseScale = pulseAnimation.value;
        final paint = Paint()
          ..color = Colors.cyan.withValues(alpha: 0.6)
          ..style = PaintingStyle.fill;
        
        canvas.drawCircle(point, 12 * pulseScale, paint);
        
        // Outer ring
        final ringPaint = Paint()
          ..color = Colors.cyan.withValues(alpha: 0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0;
        canvas.drawCircle(point, 16 * pulseScale, ringPaint);
      } else {
        // Other power points: static
        final paint = Paint()
          ..color = Colors.white.withValues(alpha: isDistanceOptimal ? 0.3 : 0.15)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(point, 7, paint);
      }
    }
  }

  /// Draw directional arrows
  void _drawDirectionalArrows(Canvas canvas, Size size, CompositionGuidanceResult result) {
    // Only show arrows when needs adjustment
    if (result.status != CompositionStatus.needsAdjustment) {
      return;
    }

    final guidance = result.directionalGuidance;
    if (!guidance.hasGuidance) {
      return;
    }

    // TODO: Make arrows use negative/inverse color of background for better visibility
    // Currently cyan/blue arrows would be invisible against blue sky backgrounds.
    // Consider: white with dark outline, or dynamically sample background color and invert.
    final arrowPaint = Paint()
      ..color = Colors.cyan.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Arrow size and position
    const arrowSize = 30.0;
    const margin = 40.0;

    // Draw arrows at edges
    if (guidance.moveLeft) {
      _drawArrow(canvas, Offset(margin, size.height / 2), arrowSize, ArrowDirection.left, arrowPaint);
    }
    if (guidance.moveRight) {
      _drawArrow(canvas, Offset(size.width - margin, size.height / 2), arrowSize, ArrowDirection.right, arrowPaint);
    }
    if (guidance.moveUp) {
      _drawArrow(canvas, Offset(size.width / 2, margin), arrowSize, ArrowDirection.up, arrowPaint);
    }
    if (guidance.moveDown) {
      _drawArrow(canvas, Offset(size.width / 2, size.height - margin), arrowSize, ArrowDirection.down, arrowPaint);
    }
  }

  /// Draw a single arrow
  void _drawArrow(Canvas canvas, Offset center, double size, ArrowDirection direction, Paint paint) {
    final path = Path();
    
    switch (direction) {
      case ArrowDirection.left:
        path.moveTo(center.dx + size / 2, center.dy);
        path.lineTo(center.dx - size / 2, center.dy - size / 2);
        path.moveTo(center.dx - size / 2, center.dy - size / 2);
        path.lineTo(center.dx - size / 2, center.dy + size / 2);
        path.moveTo(center.dx - size / 2, center.dy + size / 2);
        path.lineTo(center.dx + size / 2, center.dy);
        break;
      case ArrowDirection.right:
        path.moveTo(center.dx - size / 2, center.dy);
        path.lineTo(center.dx + size / 2, center.dy - size / 2);
        path.moveTo(center.dx + size / 2, center.dy - size / 2);
        path.lineTo(center.dx + size / 2, center.dy + size / 2);
        path.moveTo(center.dx + size / 2, center.dy + size / 2);
        path.lineTo(center.dx - size / 2, center.dy);
        break;
      case ArrowDirection.up:
        path.moveTo(center.dx, center.dy + size / 2);
        path.lineTo(center.dx - size / 2, center.dy - size / 2);
        path.moveTo(center.dx - size / 2, center.dy - size / 2);
        path.lineTo(center.dx + size / 2, center.dy - size / 2);
        path.moveTo(center.dx + size / 2, center.dy - size / 2);
        path.lineTo(center.dx, center.dy + size / 2);
        break;
      case ArrowDirection.down:
        path.moveTo(center.dx, center.dy - size / 2);
        path.lineTo(center.dx - size / 2, center.dy + size / 2);
        path.moveTo(center.dx - size / 2, center.dy + size / 2);
        path.lineTo(center.dx + size / 2, center.dy + size / 2);
        path.moveTo(center.dx + size / 2, center.dy + size / 2);
        path.lineTo(center.dx, center.dy - size / 2);
        break;
    }
    
    canvas.drawPath(path, paint);
  }


  @override
  bool shouldRepaint(CompositionGridPainter oldDelegate) {
    return oldDelegate.compositionResult != compositionResult ||
        oldDelegate.isDistanceOptimal != isDistanceOptimal;
  }
}

enum ArrowDirection {
  left,
  right,
  up,
  down,
}
