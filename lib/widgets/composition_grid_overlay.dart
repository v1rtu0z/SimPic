import 'package:flutter/material.dart';
import 'package:native_device_orientation/native_device_orientation.dart';
import '../models/composition_guidance.dart';
import '../models/distance_coaching_scenario.dart';

/// Overlay widget for composition grid and face positioning guidance
class CompositionGridOverlay extends StatefulWidget {
  final CompositionGuidanceResult? compositionResult;
  final DistanceCoachingResult? distanceResult; // Used to determine if we should show active guidance
  final Size? previewSize;
  final NativeDeviceOrientation deviceOrientation;
  final bool isOrientationMismatch;
  final int significantFaceCount;

  const CompositionGridOverlay({
    super.key,
    this.compositionResult,
    this.distanceResult,
    this.previewSize,
    required this.deviceOrientation,
    this.isOrientationMismatch = false,
    this.significantFaceCount = 0,
  });

  @override
  State<CompositionGridOverlay> createState() => _CompositionGridOverlayState();
}

class _CompositionGridOverlayState extends State<CompositionGridOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    
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
    _pulseController.dispose();
    super.dispose();
  }

  /// Check if active coaching is allowed based on priority:
  /// 1. Orientation must match (highest priority)
  /// 2. Only single face framing (composition for groups is hidden)
  ///    Exception: in landscape, we logically disable composition for groups.
  /// 3. Distance must be optimal
  bool get _isActiveGuidanceAllowed {
    if (widget.isOrientationMismatch) return false;

    // Logically disable composition coaching in landscape for groups
    final bool isLandscape = widget.deviceOrientation == NativeDeviceOrientation.landscapeLeft ||
        widget.deviceOrientation == NativeDeviceOrientation.landscapeRight;
    if (isLandscape && widget.significantFaceCount >= 2) return false;
    
    // Original multi-face check (still apply for portrait if we want to be consistent)
    if (widget.significantFaceCount >= 2) return false;

    // If distance coaching is enabled, it must be optimal
    if (widget.distanceResult != null) {
      return widget.distanceResult!.status == DistanceCoachingStatus.optimal;
    }
    // If distance coaching is disabled (distanceResult is null), allow composition coaching
    return true;
  }

  @override
  Widget build(BuildContext context) {
    // Always show grid (subtle), but only show active guidance when allowed by priority
    if (widget.previewSize == null) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      width: widget.previewSize!.width,
      height: widget.previewSize!.height,
      child: CustomPaint(
        painter: CompositionGridPainter(
          compositionResult: widget.compositionResult,
          isActiveGuidanceAllowed: _isActiveGuidanceAllowed,
          pulseAnimation: _pulseAnimation,
          deviceOrientation: widget.deviceOrientation,
        ),
      ),
    );
  }
}

/// Custom painter for composition grid overlay
class CompositionGridPainter extends CustomPainter {
  final CompositionGuidanceResult? compositionResult;
  final bool isActiveGuidanceAllowed;
  final Animation<double> pulseAnimation;
  final NativeDeviceOrientation deviceOrientation;

  CompositionGridPainter({
    required this.compositionResult,
    required this.isActiveGuidanceAllowed,
    required this.pulseAnimation,
    required this.deviceOrientation,
  }) : super(repaint: pulseAnimation);

  @override
  void paint(Canvas canvas, Size size) {
    // Calculate power points in screen coordinates
    final powerPoints = _calculatePowerPoints(size);
    
    // Draw grid lines (always visible, subtle)
    _drawGridLines(canvas, size);
    
    // Draw power points
    _drawPowerPoints(canvas, size, powerPoints);
    
    // Draw directional arrows (only when active guidance is allowed AND needs adjustment)
    if (isActiveGuidanceAllowed && 
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

    // Composition guidance is already calculated in portrait preview space.
    // Do not rotate it again here or the highlighted target point drifts.
    final targetUpright = compositionResult!.nearestPowerPoint;
    final targetX = targetUpright.x;
    final targetY = targetUpright.y;
    
    // Draw all power points
    for (final point in powerPoints) {
      // Calculate normalized coordinates for this power point (always portrait)
      final pointNormalizedX = point.dx / size.width;
      final pointNormalizedY = point.dy / size.height;
      
      // Match power point by comparing normalized coordinates
      const tolerance = 0.05; // Increased tolerance for power point matching
      final isTarget = (pointNormalizedX - targetX).abs() < tolerance &&
                       (pointNormalizedY - targetY).abs() < tolerance;
      
      // Only highlight target power point when active guidance is allowed AND composition needs adjustment
      if (isTarget && 
          isActiveGuidanceAllowed && 
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
          ..color = Colors.white.withValues(alpha: isActiveGuidanceAllowed ? 0.3 : 0.15)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(point, 7, paint);
      }
    }
  }

  /// Draw directional arrows
  void _drawDirectionalArrows(Canvas canvas, Size size, CompositionGuidanceResult result) {
    // Only show arrows when allowed AND needs adjustment
    if (!isActiveGuidanceAllowed || result.status != CompositionStatus.needsAdjustment) {
      return;
    }

    final guidance = result.directionalGuidance;
    if (!guidance.hasGuidance) {
      return;
    }

    // Arrow size and position
    const arrowSize = 30.0;
    const margin = 40.0;

    // Get normalized pulse value (0.0 to 1.0)
    final pulseValue = (pulseAnimation.value - 1.0) / 0.2;

    // Directional guidance is already expressed in portrait preview space.
    if (guidance.moveLeft) {
      _drawArrow(canvas, Offset(margin, size.height / 2), arrowSize, ArrowDirection.left, pulseValue);
    }
    if (guidance.moveRight) {
      _drawArrow(canvas, Offset(size.width - margin, size.height / 2), arrowSize, ArrowDirection.right, pulseValue);
    }
    if (guidance.moveUp) {
      _drawArrow(canvas, Offset(size.width / 2, margin), arrowSize, ArrowDirection.up, pulseValue);
    }
    if (guidance.moveDown) {
      _drawArrow(canvas, Offset(size.width / 2, size.height - margin), arrowSize, ArrowDirection.down, pulseValue);
    }
  }

  /// Draw a single arrow with outline for better visibility
  void _drawArrow(Canvas canvas, Offset center, double size, ArrowDirection direction, double pulseValue) {
    final path = Path();
    
    // Scale arrow size slightly with pulse
    final currentSize = size * (0.9 + 0.2 * pulseValue);
    
    switch (direction) {
      case ArrowDirection.left:
        path.moveTo(center.dx + currentSize / 2, center.dy);
        path.lineTo(center.dx - currentSize / 2, center.dy - currentSize / 2);
        path.lineTo(center.dx - currentSize / 2, center.dy + currentSize / 2);
        path.close();
        break;
      case ArrowDirection.right:
        path.moveTo(center.dx - currentSize / 2, center.dy);
        path.lineTo(center.dx + currentSize / 2, center.dy - currentSize / 2);
        path.lineTo(center.dx + currentSize / 2, center.dy + currentSize / 2);
        path.close();
        break;
      case ArrowDirection.up:
        path.moveTo(center.dx, center.dy + currentSize / 2);
        path.lineTo(center.dx - currentSize / 2, center.dy - currentSize / 2);
        path.lineTo(center.dx + currentSize / 2, center.dy - currentSize / 2);
        path.close();
        break;
      case ArrowDirection.down:
        path.moveTo(center.dx, center.dy - currentSize / 2);
        path.lineTo(center.dx - currentSize / 2, center.dy + currentSize / 2);
        path.lineTo(center.dx + currentSize / 2, center.dy + currentSize / 2);
        path.close();
        break;
    }
    
    // Draw black outline
    final outlinePaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, outlinePaint);
    
    // Draw cyan fill (matching composition circle)
    final fillPaint = Paint()
      ..color = Colors.cyan.withValues(alpha: 0.8)
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);
    
    // Draw a subtle inner glow based on pulse to enhance animation
    final glowPaint = Paint()
      ..color = Colors.cyan.withValues(alpha: 0.4 * pulseValue)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawPath(path, glowPaint);
  }


  @override
  bool shouldRepaint(CompositionGridPainter oldDelegate) {
    return oldDelegate.compositionResult != compositionResult ||
        oldDelegate.isActiveGuidanceAllowed != isActiveGuidanceAllowed ||
        oldDelegate.deviceOrientation != deviceOrientation;
  }
}

enum ArrowDirection {
  left,
  right,
  up,
  down,
}
