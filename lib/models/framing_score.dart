import 'dart:math';
import 'package:flutter/material.dart';
import 'distance_coaching_scenario.dart';
import 'composition_guidance.dart';
import 'exposure_guidance.dart';
import 'blink_detection.dart';

class FramingScoreResult {
  final double totalScore; // 0-100
  final double distanceScore; // 0-40
  final double positionScore; // 0-30
  final double lightingScore; // 0-30
  final String message;
  final Color color;

  const FramingScoreResult({
    required this.totalScore,
    required this.distanceScore,
    required this.positionScore,
    required this.lightingScore,
    required this.message,
    required this.color,
  });

  bool get isGreat => totalScore > 80;
  bool get isGood => totalScore >= 60 && totalScore <= 80;
  bool get isNeedsAdjustment => totalScore < 60;
}

FramingScoreResult calculateFramingScore({
  DistanceCoachingResult? distanceResult,
  CompositionGuidanceResult? compositionResult,
  FaceExposureResult? exposureResult,
  BlinkDetectionResult? blinkResult,
}) {
  // 1. Distance Score (40 points)
  double distanceScore = 0;
  if (distanceResult != null) {
    if (distanceResult.status == DistanceCoachingStatus.optimal) {
      distanceScore = 40;
    } else {
      // Logic: optimal = 40, too far/close = 0-25
      // If it's not optimal, it's a significant framing issue
      distanceScore = 15; 
    }
  }

  // 2. Position Score (30 points)
  double positionScore = 0;
  if (compositionResult != null) {
    if (compositionResult.status == CompositionStatus.wellPositioned) {
      positionScore = 30;
    } else {
      // Logic: on power point = 30, off = 0-20
      // distancePercentage in compositionResult is normalized distance (0 to ~1.414)
      // 0.15 is the threshold for wellPositioned
      double dist = compositionResult.distancePercentage;
      positionScore = max(0, 20 * (1.0 - min(1.0, dist / 0.5)));
    }
  }

  // 3. Lighting Score (30 points)
  double lightingScore = 0;
  if (exposureResult != null) {
    if (exposureResult.status == ExposureStatus.good) {
      lightingScore = 30;
    } else if (exposureResult.status == ExposureStatus.underexposed) {
      lightingScore = 20;
    } else if (exposureResult.status == ExposureStatus.backlit || 
               exposureResult.status == ExposureStatus.shadowed) {
      // Critical lighting issues - should penalize more to prevent "Great shot"
      lightingScore = 5;
    }
  } else {
    // If no face detected, we can't really score lighting well, but let's assume baseline
    lightingScore = 15;
  }

  double totalScore = distanceScore + positionScore + lightingScore;
  
  // 4. Blink Penalty
  // If eyes are closed, we cannot have a "Great shot"
  if (blinkResult != null && blinkResult.eitherEyeClosed) {
    totalScore = min(totalScore, 70); // Force out of "Great" range
  }
  
  String message;
  Color color;
  
  if (totalScore > 80) {
    message = "Great shot!";
    color = Colors.green;
  } else if (totalScore >= 60) {
    message = "Good";
    color = Colors.yellow;
  } else {
    message = "Needs adjustment";
    color = Colors.red;
  }

  return FramingScoreResult(
    totalScore: totalScore,
    distanceScore: distanceScore,
    positionScore: positionScore,
    lightingScore: lightingScore,
    message: message,
    color: color,
  );
}
