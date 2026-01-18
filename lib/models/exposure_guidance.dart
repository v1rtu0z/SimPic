import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

enum ExposureStatus {
  good,
  backlit,
  shadowed,
  underexposed,
}

class FaceExposureResult {
  final ExposureStatus status;
  final double faceBrightness;
  final double backgroundBrightness;
  final double ratio;
  final double stdDev;
  final String message;

  const FaceExposureResult({
    required this.status,
    required this.faceBrightness,
    required this.backgroundBrightness,
    required this.ratio,
    required this.stdDev,
    required this.message,
  });

  bool get isGood => status == ExposureStatus.good;
}

FaceExposureResult analyzeFaceExposure(
  CameraImage image,
  Rect faceRect,
  int rotationDegrees,
  bool isFrontCamera,
) {
  // 1. Convert faceRect (in preview/display coordinates) back to image coordinates
  // ML Kit bounding box is already in image coordinates, but we might need to handle rotation
  // Actually, in CameraScreen, bestFace.boundingBox is used.
  // It is in image coordinates.

  final List<double> faceLuminances = [];
  final List<double> haloLuminances = [];

  final int width = image.width;
  final int height = image.height;
  final Uint8List yPlane = image.planes[0].bytes;
  final int yRowStride = image.planes[0].bytesPerRow;

  // Face bounding box in image coordinates
  final int left = faceRect.left.toInt().clamp(0, width - 1);
  final int top = faceRect.top.toInt().clamp(0, height - 1);
  final int right = faceRect.right.toInt().clamp(0, width - 1);
  final int bottom = faceRect.bottom.toInt().clamp(0, height - 1);

  // Sample face region (grid sampling for performance)
  const int step = 4;
  for (int y = top; y < bottom; y += step) {
    for (int x = left; x < right; x += step) {
      final int index = y * yRowStride + x;
      faceLuminances.add(yPlane[index] / 255.0);
    }
  }

  // Sample halo region (surrounding the face)
  final int haloPaddingW = (faceRect.width * 0.5).toInt();
  final int haloPaddingH = (faceRect.height * 0.5).toInt();
  
  final Rect haloRect = Rect.fromLTRB(
    (faceRect.left - haloPaddingW).clamp(0, width - 1).toDouble(),
    (faceRect.top - haloPaddingH).clamp(0, height - 1).toDouble(),
    (faceRect.right + haloPaddingW).clamp(0, width - 1).toDouble(),
    (faceRect.bottom + haloPaddingH).clamp(0, height - 1).toDouble(),
  );

  for (int y = haloRect.top.toInt(); y < haloRect.bottom.toInt(); y += step) {
    for (int x = haloRect.left.toInt(); x < haloRect.right.toInt(); x += step) {
      // Skip if inside face rect
      if (x >= left && x <= right && y >= top && y <= bottom) continue;
      
      final int index = y * yRowStride + x;
      haloLuminances.add(yPlane[index] / 255.0);
    }
  }

  if (faceLuminances.isEmpty) {
    return const FaceExposureResult(
      status: ExposureStatus.good,
      faceBrightness: 0.5,
      backgroundBrightness: 0.5,
      ratio: 1.0,
      stdDev: 0.0,
      message: "",
    );
  }

  final double avgFace = faceLuminances.reduce((a, b) => a + b) / faceLuminances.length;
  final double avgHalo = haloLuminances.isEmpty 
      ? avgFace 
      : haloLuminances.reduce((a, b) => a + b) / haloLuminances.length;
  
  final double ratio = avgHalo > 0 ? avgFace / avgHalo : 1.0;
  
  // Calculate Standard Deviation for harsh shadow detection
  double variance = 0;
  for (final l in faceLuminances) {
    variance += pow(l - avgFace, 2);
  }
  final double stdDev = sqrt(variance / faceLuminances.length);

  // Logic from requirements:
  // Backlit detection: Face much darker than background (ratio < 0.6)
  // Harsh shadow detection: Significant brightness variance within face region (std dev > threshold)
  // Good lighting: Face slightly brighter than background (ratio 1.1-1.3)
  
  // P0 Thresholds
  const double backlitThreshold = 0.6;
  const double harshShadowThreshold = 0.15; // Tuned value for normalized brightness (0-1)
  const double minGoodRatio = 1.0; // Adjusted from 1.1 to be more lenient in practice
  const double maxGoodRatio = 1.5; // Adjusted from 1.3

  if (ratio < backlitThreshold) {
    return FaceExposureResult(
      status: ExposureStatus.backlit,
      faceBrightness: avgFace,
      backgroundBrightness: avgHalo,
      ratio: ratio,
      stdDev: stdDev,
      message: "☀️ Backlit - turn around or use flash",
    );
  }

  if (stdDev > harshShadowThreshold) {
    return FaceExposureResult(
      status: ExposureStatus.shadowed,
      faceBrightness: avgFace,
      backgroundBrightness: avgHalo,
      ratio: ratio,
      stdDev: stdDev,
      message: "⚠️ Face in shadow - move to brighter area",
    );
  }

  if (avgFace < 0.25) {
     return FaceExposureResult(
      status: ExposureStatus.underexposed,
      faceBrightness: avgFace,
      backgroundBrightness: avgHalo,
      ratio: ratio,
      stdDev: stdDev,
      message: "⚠️ Too dark - find more light",
    );
  }

  // Check for good lighting
  if (ratio >= minGoodRatio && ratio <= maxGoodRatio) {
     return FaceExposureResult(
      status: ExposureStatus.good,
      faceBrightness: avgFace,
      backgroundBrightness: avgHalo,
      ratio: ratio,
      stdDev: stdDev,
      message: "✓ Good lighting",
    );
  }

  // Default fallback if none of the above matches exactly
  return FaceExposureResult(
    status: ExposureStatus.good,
    faceBrightness: avgFace,
    backgroundBrightness: avgHalo,
    ratio: ratio,
    stdDev: stdDev,
    message: "",
  );
}
