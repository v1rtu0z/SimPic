import 'package:flutter/material.dart';
import '../models/portrait_analysis.dart';

/// Portrait mode indicator widget with smooth animations
class PortraitIndicator extends StatelessWidget {
  final PortraitAnalysisResult? portraitResult;
  final bool showDebugOverlay;

  const PortraitIndicator({
    super.key,
    this.portraitResult,
    this.showDebugOverlay = false,
  });

  @override
  Widget build(BuildContext context) {
    if (portraitResult == null) {
      return const SizedBox.shrink();
    }

    return Stack(
      children: [
        // Main portrait badge
        if (portraitResult!.isActive)
          _buildPortraitBadge(),

        // Debug overlay (if enabled)
        if (showDebugOverlay && portraitResult!.debugInfo != null)
          _buildDebugOverlay(portraitResult!.debugInfo!),
      ],
    );
  }

  Widget _buildPortraitBadge() {
    return Positioned(
      top: 120, // Below settings/flash buttons
      left: 0,
      right: 0,
      child: SafeArea(
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.purpleAccent.withValues(alpha: 0.8),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.purpleAccent.withValues(alpha: 0.3),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.camera_alt,
                  color: Colors.purpleAccent,
                  size: 24,
                ),
                const SizedBox(width: 8),
                const Text(
                  'PORTRAIT',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDebugOverlay(PortraitDebugInfo debugInfo) {
    return Positioned(
      top: 180,
      left: 16,
      right: 16,
      child: SafeArea(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.orange.withValues(alpha: 0.6),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'PORTRAIT DEBUG',
                style: TextStyle(
                  color: Colors.orange,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Blue box = central 60% zone (portrait area)',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 9,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const Text(
                'Red/Orange/Green box = detected face (color = status)',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 9,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const Text(
                'Portrait works if face is centered OR well-composed',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 9,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 8),
              _buildDebugRow('Face Size', '${(debugInfo.faceSizeRatio * 100).toStringAsFixed(1)}% (need 20-55%, selfie: 20-66%)'),
              _buildDebugRow('Center Distance', '${(debugInfo.distanceFromCenter * 100).toStringAsFixed(1)}% (max 30%)'),
              _buildDebugRow('Composition', debugInfo.isWellComposed == true 
                  ? '✓ Well-composed (rule of thirds)' 
                  : debugInfo.isWellComposed == false 
                      ? '✗ Not well-composed' 
                      : '? (not checked)'),
              _buildDebugRow('Movement', debugInfo.actualMovementPercent != null 
                  ? '${debugInfo.actualMovementPercent!.toStringAsFixed(2)}% (threshold: ${(PortraitThresholds.maxMovementDelta * 100).toStringAsFixed(0)}%)'
                  : '0.00% (first frame)'),
              _buildDebugRow('Stable', debugInfo.stabilityFactor < 1.0 && debugInfo.actualMovementPercent != null && debugInfo.actualMovementPercent! < (PortraitThresholds.maxMovementDelta * 100)
                  ? '✓ Yes' 
                  : debugInfo.actualMovementPercent == null 
                      ? '? (calculating...)'
                      : '✗ No (${debugInfo.actualMovementPercent!.toStringAsFixed(2)}% ≥ ${(PortraitThresholds.maxMovementDelta * 100).toStringAsFixed(0)}%)'),
              _buildDebugRow('Frames', '${debugInfo.consecutiveFrameCount}/${PortraitThresholds.activationFrameCount}'),
              _buildDebugRow('Hardware Bokeh', debugInfo.isHardwareExtensionAvailable ? 'Available' : 'Not Available'),
              if (debugInfo.failureReason != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Reason: ${debugInfo.failureReason}',
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 10,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              // Confidence progress bar
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Confidence: ${(portraitResult!.confidenceScore * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: portraitResult!.confidenceScore,
                      backgroundColor: Colors.white24,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        portraitResult!.confidenceScore > 0.8
                            ? Colors.green
                            : portraitResult!.confidenceScore > 0.5
                                ? Colors.orange
                                : Colors.red,
                      ),
                      minHeight: 6,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDebugRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 10,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

/// Debug overlay for portrait candidate zone visualization
class PortraitDebugOverlay extends CustomPainter {
  final PortraitAnalysisResult? portraitResult;
  final Size imageSize;
  final Rect? faceBoundingBox;

  PortraitDebugOverlay({
    required this.portraitResult,
    required this.imageSize,
    this.faceBoundingBox,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (portraitResult == null) return;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    // Draw central 60% zone (portrait candidate area)
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final zoneWidth = size.width * 0.6;
    final zoneHeight = size.height * 0.6;

    paint.color = Colors.blue.withValues(alpha: 0.3);
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(centerX, centerY),
        width: zoneWidth,
        height: zoneHeight,
      ),
      paint,
    );

    // Draw face bounding box (the "red rectangle" the user sees)
    // Color coding:
    // - Green: Portrait mode is ACTIVE (all criteria met, stable for 15+ frames)
    // - Orange: Portrait CANDIDATE (meets criteria but not stable yet)
    // - Red: NOT a candidate (fails one or more criteria: size, position, or multiple faces)
    if (faceBoundingBox != null) {
      final isCandidate = portraitResult!.isPortraitCandidate;
      final isActive = portraitResult!.isActive;

      paint.color = isActive
          ? Colors.green.withValues(alpha: 0.8)
          : isCandidate
              ? Colors.orange.withValues(alpha: 0.6)
              : Colors.red.withValues(alpha: 0.4);

      paint.strokeWidth = isActive ? 3.0 : 2.0;
      canvas.drawRect(faceBoundingBox!, paint);

      // Draw face center point
      final faceCenter = Offset(
        faceBoundingBox!.left + faceBoundingBox!.width / 2,
        faceBoundingBox!.top + faceBoundingBox!.height / 2,
      );
      paint.style = PaintingStyle.fill;
      paint.color = isActive ? Colors.green : Colors.orange;
      canvas.drawCircle(faceCenter, 4, paint);
    }
  }

  @override
  bool shouldRepaint(PortraitDebugOverlay oldDelegate) {
    return oldDelegate.portraitResult != portraitResult ||
        oldDelegate.faceBoundingBox != faceBoundingBox;
  }
}
