/// Distance coaching scenario types based on portrait framing
enum DistanceCoachingScenario {
  closeUpPortrait,
  waistUp,
  fullBody,
  groupPhoto,
}

/// Threshold ranges for each scenario type
class ScenarioThresholds {
  final double optimalMin;
  final double optimalMax;
  final double tooSmall;
  final double tooLarge;

  const ScenarioThresholds({
    required this.optimalMin,
    required this.optimalMax,
    required this.tooSmall,
    required this.tooLarge,
  });
}

/// Threshold definitions for each scenario
class DistanceCoachingThresholds {
  static const Map<DistanceCoachingScenario, ScenarioThresholds> thresholds = {
    DistanceCoachingScenario.closeUpPortrait: ScenarioThresholds(
      optimalMin: 30.0,
      optimalMax: 45.0,
      tooSmall: 25.0,
      tooLarge: 50.0,
    ),
    DistanceCoachingScenario.waistUp: ScenarioThresholds(
      optimalMin: 15.0,
      optimalMax: 22.0,
      tooSmall: 12.0,
      tooLarge: 25.0,
    ),
    DistanceCoachingScenario.fullBody: ScenarioThresholds(
      optimalMin: 8.0,
      optimalMax: 12.0,
      tooSmall: 5.0,
      tooLarge: 15.0,
    ),
    DistanceCoachingScenario.groupPhoto: ScenarioThresholds(
      optimalMin: 10.0,
      optimalMax: 20.0,
      tooSmall: 7.0,
      tooLarge: 25.0,
    ),
  };

  /// Detect scenario based on face height percentage of frame height
  /// 
  /// Uses hysteresis to prevent flickering between scenarios:
  /// - Close-up: >= 25%
  /// - Waist-up: 12-25%
  /// - Full body: < 12%
  static DistanceCoachingScenario detectScenario(
    double faceHeightPercentage, {
    DistanceCoachingScenario? currentScenario,
  }) {
    // Use hysteresis: require crossing boundary by 2% to switch scenarios
    if (currentScenario == DistanceCoachingScenario.closeUpPortrait) {
      // If currently close-up, require < 23% to switch down
      if (faceHeightPercentage < 23.0) {
        if (faceHeightPercentage >= 12.0) {
          return DistanceCoachingScenario.waistUp;
        } else {
          return DistanceCoachingScenario.fullBody;
        }
      }
      return DistanceCoachingScenario.closeUpPortrait;
    } else if (currentScenario == DistanceCoachingScenario.waistUp) {
      // If currently waist-up, check boundaries with hysteresis
      if (faceHeightPercentage >= 27.0) {
        return DistanceCoachingScenario.closeUpPortrait;
      } else if (faceHeightPercentage < 10.0) {
        return DistanceCoachingScenario.fullBody;
      }
      return DistanceCoachingScenario.waistUp;
    } else {
      // Currently full body or no current scenario
      if (faceHeightPercentage >= 14.0) {
        if (faceHeightPercentage >= 25.0) {
          return DistanceCoachingScenario.closeUpPortrait;
        } else {
          return DistanceCoachingScenario.waistUp;
        }
      }
      return DistanceCoachingScenario.fullBody;
    }
  }

  /// Get thresholds for a given scenario
  static ScenarioThresholds getThresholds(DistanceCoachingScenario scenario) {
    return thresholds[scenario]!;
  }
}

/// Distance coaching status
enum DistanceCoachingStatus {
  tooClose,
  tooFar,
  optimal,
}

/// Distance coaching result containing status and message
class DistanceCoachingResult {
  final DistanceCoachingStatus status;
  final String message;
  final DistanceCoachingScenario scenario;

  const DistanceCoachingResult({
    required this.status,
    required this.message,
    required this.scenario,
  });
}

/// Evaluate distance coaching based on face height percentage
DistanceCoachingResult evaluateDistanceCoaching(
  double faceHeightPercentage,
  DistanceCoachingScenario? currentScenario, {
  int significantFaceCount = 1,
}) {
  // Detect scenario with hysteresis
  DistanceCoachingScenario scenario;
  
  if (significantFaceCount >= 2) {
    // Force group photo scenario when multiple people are detected
    scenario = DistanceCoachingScenario.groupPhoto;
  } else {
    scenario = DistanceCoachingThresholds.detectScenario(
      faceHeightPercentage,
      currentScenario: currentScenario,
    );
  }

  final thresholds = DistanceCoachingThresholds.getThresholds(scenario);

  // Determine status
  DistanceCoachingStatus status;
  String message;

  if (faceHeightPercentage < thresholds.tooSmall) {
    status = DistanceCoachingStatus.tooFar;
    message = 'MOVE CLOSER';
  } else if (faceHeightPercentage > thresholds.tooLarge) {
    status = DistanceCoachingStatus.tooClose;
    message = 'STEP BACK';
  } else if (faceHeightPercentage >= thresholds.optimalMin &&
      faceHeightPercentage <= thresholds.optimalMax) {
    status = DistanceCoachingStatus.optimal;
    message = 'Good distance';
  } else {
    // In acceptable range but not optimal
    if (faceHeightPercentage < thresholds.optimalMin) {
      status = DistanceCoachingStatus.tooFar;
      message = 'Move closer';
    } else {
      status = DistanceCoachingStatus.tooClose;
      message = 'Step back';
    }
  }

  return DistanceCoachingResult(
    status: status,
    message: message,
    scenario: scenario,
  );
}
