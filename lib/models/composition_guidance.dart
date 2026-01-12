import 'dart:math';
import 'package:flutter/material.dart';

/// Represents a rule-of-thirds power point (intersection point)
class PowerPoint {
  final double x; // Normalized 0-1
  final double y; // Normalized 0-1

  const PowerPoint({required this.x, required this.y});

  /// Convert to screen coordinates
  Offset toScreenOffset(Size frameSize) {
    return Offset(x * frameSize.width, y * frameSize.height);
  }

  /// Check if two power points are equal (within floating point tolerance)
  bool equals(PowerPoint other, {double tolerance = 0.001}) {
    return (x - other.x).abs() < tolerance && (y - other.y).abs() < tolerance;
  }

  @override
  String toString() => 'PowerPoint($x, $y)';
}

/// Composition guidance status
enum CompositionStatus {
  wellPositioned,
  needsAdjustment,
}

/// Directional guidance for moving camera
class DirectionalGuidance {
  final bool moveLeft;
  final bool moveRight;
  final bool moveUp;
  final bool moveDown;

  const DirectionalGuidance({
    this.moveLeft = false,
    this.moveRight = false,
    this.moveUp = false,
    this.moveDown = false,
  });

  bool get hasGuidance => moveLeft || moveRight || moveUp || moveDown;
}

/// Composition guidance result
class CompositionGuidanceResult {
  final CompositionStatus status;
  final PowerPoint nearestPowerPoint;
  final double distancePercentage; // Normalized distance (0 to ~1.414), not percentage
  final DirectionalGuidance directionalGuidance;
  final String? message; // Optional message like "Perfect positioning!"

  const CompositionGuidanceResult({
    required this.status,
    required this.nearestPowerPoint,
    required this.distancePercentage,
    required this.directionalGuidance,
    this.message,
  });
}

/// Calculate the 4 rule-of-thirds power points
List<PowerPoint> calculatePowerPoints(Size frameSize) {
  // Rule of thirds: lines at 1/3 and 2/3
  // Power points are at intersections
  const third = 1.0 / 3.0;
  const twoThirds = 2.0 / 3.0;

  return [
    PowerPoint(x: third, y: third),        // Top-left
    PowerPoint(x: twoThirds, y: third),    // Top-right
    PowerPoint(x: third, y: twoThirds),    // Bottom-left
    PowerPoint(x: twoThirds, y: twoThirds), // Bottom-right
  ];
}

/// Find the nearest power point to the face center
/// Uses hysteresis to prevent flickering when close to a power point
/// All calculations are done in normalized coordinates (0-1) to avoid coordinate system mismatches
PowerPoint findNearestPowerPoint(
  Offset faceCenter,
  List<PowerPoint> powerPoints,
  Size frameSize, {
  PowerPoint? previousPowerPoint,
}) {
  // ITERATION 4: Verify coordinate system
  // Coordinate system: (0,0) at top-left, X increases right, Y increases downward
  // ML Kit bounding box uses same coordinate system
  // Normalization: faceCenter.dx / frameSize.width gives 0-1 X coordinate
  //                faceCenter.dy / frameSize.height gives 0-1 Y coordinate
  // Bottom power points are at Y = 2/3 = 0.667 (two-thirds down the frame)
  // If face is at bottom of image, normalized Y should be close to 1.0
  // If face is at bottom power point, normalized Y should be close to 0.667
  // Normalize face center to (0-1) coordinates to match power points
  final normalizedFaceCenter = Offset(
    faceCenter.dx / frameSize.width,
    faceCenter.dy / frameSize.height,
  );
  
  double minDistance = double.infinity;
  PowerPoint nearest = powerPoints.first;
  Map<PowerPoint, double> distances = {};

  // Calculate distance to all power points
  for (final powerPoint in powerPoints) {
    // Calculate distance accounting for aspect ratio to find the TRULY nearest point in pixel space
    final distance = calculateDistanceToPowerPoint(normalizedFaceCenter, powerPoint, frameSize);
    
    distances[powerPoint] = distance;

    if (distance < minDistance) {
      minDistance = distance;
      nearest = powerPoint;
    }
  }

  // ITERATION 5 FINAL FIX: Re-enabled hysteresis with improvements
  // Fix: Reduced hysteresis threshold and added check for clearly closer power point
  // This prevents flickering while still allowing correct selection when face moves to a different power point
  if (previousPowerPoint != null && !nearest.equals(previousPowerPoint)) {
    // Find the distance to the previous power point
    double? previousDistance = distances[previousPowerPoint];
    if (previousDistance == null) {
      // Calculate distance if not found in cache (shouldn't happen, but be safe)
      previousDistance = sqrt(
        pow(normalizedFaceCenter.dx - previousPowerPoint.x, 2) +
        pow(normalizedFaceCenter.dy - previousPowerPoint.y, 2),
      );
    }
    
    // FIX: Reduced hysteresis to allow easier switching between power points
    // If new power point is closer (even slightly), switch to it
    // This prevents getting stuck on one power point (like top-right)
    const hysteresisThreshold = 0.02; // Very small - only prevent flickering when distances are almost equal
    const clearSwitchThreshold = 0.05; // If new PP is 5% closer, always switch (reduced from 0.10)
    
    // Always switch if new power point is clearly closer
    if (minDistance < previousDistance - clearSwitchThreshold) {
      // New power point is clearly closer - switch immediately
      return nearest;
    }
    
    // Otherwise, use minimal hysteresis to prevent flickering only when distances are nearly equal
    if (minDistance > previousDistance - hysteresisThreshold) {
      // Distances are very similar - keep previous to prevent flickering
      // Find the actual PowerPoint instance from the list that matches previousPowerPoint
      for (final pp in powerPoints) {
        if (pp.equals(previousPowerPoint)) {
          return pp;
        }
      }
      return previousPowerPoint; // Fallback
    }
    // If we get here, new power point is closer (by more than hysteresisThreshold), so switch
  }

  return nearest;
}

/// Calculate normalized distance to power point
/// Returns distance accounting for aspect ratio to ensure consistent pixel distance
/// FIX: The issue is that mixing normalized X and Y creates inconsistent pixel distances
/// Solution: Scale the distance calculation to account for aspect ratio
double calculateDistanceToPowerPoint(
  Offset normalizedFaceCenter,  // Already normalized (0-1) coordinates!
  PowerPoint powerPoint,
  Size frameSize,
) {
  // Calculate differences in normalized space
  final dxNorm = normalizedFaceCenter.dx - powerPoint.x;
  final dyNorm = normalizedFaceCenter.dy - powerPoint.y;
  
  // FIX: Account for aspect ratio by scaling Y component
  // This ensures that the same pixel distance in X and Y contributes equally
  // For a 720x1280 frame: aspectRatio = 720/1280 = 0.5625
  // We scale Y by (1/aspectRatio) so that pixel distances are equivalent in normalized X space
  final aspectRatio = frameSize.width / frameSize.height;
  final dxScaled = dxNorm;
  final dyScaled = dyNorm / aspectRatio; // Scale Y to match X scale (dyNorm * height/width)
  
  // Calculate distance with aspect-ratio-corrected components
  final distance = sqrt(dxScaled * dxScaled + dyScaled * dyScaled);

  return distance; // Return aspect-ratio-corrected distance
}

/// Calculate directional guidance (which way to move camera)
/// All calculations are done in normalized coordinates (0-1) to avoid coordinate system mismatches
DirectionalGuidance calculateDirectionalGuidance(
  Offset faceCenter,
  PowerPoint targetPowerPoint,
  Size frameSize,
) {
  // Normalize face center to (0-1) coordinates to match power points
  final normalizedFaceCenter = Offset(
    faceCenter.dx / frameSize.width,
    faceCenter.dy / frameSize.height,
  );
  
  // Calculate differences in normalized space
  final dx = targetPowerPoint.x - normalizedFaceCenter.dx;
  final dy = targetPowerPoint.y - normalizedFaceCenter.dy;
  
  // ITERATION 5 FINAL FIX: Verified directional guidance logic is correct
  // dx/dy calculations and signs are correct:
  // - If dx > 0: target is to the right, so moveRight = true (CORRECT)
  // - If dx < 0: target is to the left, so moveLeft = true (CORRECT)
  // - If dy > 0: target is below, so moveDown = true (CORRECT)
  // - If dy < 0: target is above, so moveUp = true (CORRECT)
  
  // Threshold: only show arrow if difference is significant (>5% in normalized space)
  const threshold = 0.05;
  
  // ITERATION 5 FINAL FIX: Suppress all guidance when very close to power point
  // This prevents arrows from showing when face is essentially at the power point
  // Calculate distance to determine if we're very close
  final distance = sqrt(dx * dx + dy * dy);
  const veryCloseThreshold = 0.03; // 3% in normalized space - suppress arrows when this close
  
  if (distance < veryCloseThreshold) {
    // Too close - no guidance needed
    return const DirectionalGuidance();
  }
  
  return DirectionalGuidance(
    moveLeft: dx < -threshold,
    moveRight: dx > threshold,
    moveUp: dy < -threshold,
    moveDown: dy > threshold,
  );
}

/// Evaluate composition and return guidance result
CompositionGuidanceResult evaluateComposition(
  Offset faceCenter,
  Size frameSize, {
  PowerPoint? previousPowerPoint,
}) {
  // Calculate power points
  final powerPoints = calculatePowerPoints(frameSize);
  
  // Find nearest power point (with hysteresis to prevent flickering)
  final nearestPowerPoint = findNearestPowerPoint(
    faceCenter, 
    powerPoints, 
    frameSize,
    previousPowerPoint: previousPowerPoint,
  );
  
  final normalizedFaceCenter = Offset(
    faceCenter.dx / frameSize.width,
    faceCenter.dy / frameSize.height,
  );

  // Calculate distance (now accounts for aspect ratio in the distance calculation)
  final distance = calculateDistanceToPowerPoint(normalizedFaceCenter, nearestPowerPoint, frameSize);
  
  // FIX: Now that distance accounts for aspect ratio, we can use a simple threshold
  // The distance is now in "aspect-ratio-corrected normalized space" where
  // X and Y components are on the same scale (both scaled to width).
  // So a threshold of 0.15 means 15% of frame width in both directions.
  const threshold = 0.15; // 15% of frame width (since Y is scaled to match X scale)
  final isWellPositioned = distance < threshold;
  
  // Calculate directional guidance
  final directionalGuidance = calculateDirectionalGuidance(
    faceCenter,
    nearestPowerPoint,
    frameSize,
  );
  
  // Determine status and message
  final status = isWellPositioned 
      ? CompositionStatus.wellPositioned 
      : CompositionStatus.needsAdjustment;
  
  final message = isWellPositioned 
      ? 'Perfect positioning!' 
      : null;
  
  return CompositionGuidanceResult(
    status: status,
    nearestPowerPoint: nearestPowerPoint,
    distancePercentage: distance, // Keep field name for compatibility, but now contains raw distance
    directionalGuidance: directionalGuidance,
    message: message,
  );
}
