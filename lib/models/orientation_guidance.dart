import 'package:native_device_orientation/native_device_orientation.dart';

/// Suggestion for camera orientation based on face count
enum OrientationSuggestion {
  portrait,
  landscape,
  none,
}

/// Result of orientation guidance evaluation
class OrientationGuidance {
  final OrientationSuggestion suggestedOrientation;
  final bool isMismatch;

  const OrientationGuidance({
    required this.suggestedOrientation,
    required this.isMismatch,
  });

  /// Evaluate the orientation suggestion based on the number of significant faces
  /// and the current device orientation.
  static OrientationGuidance evaluate({
    required int significantFaceCount,
    required NativeDeviceOrientation currentOrientation,
  }) {
    OrientationSuggestion suggestion = OrientationSuggestion.none;
    
    // Logic: 
    // - 1 face: Suggest Portrait (optimized for single subject)
    // - 2+ faces: Suggest Landscape (optimized for groups/wider context)
    if (significantFaceCount == 1) {
      suggestion = OrientationSuggestion.portrait;
    } else if (significantFaceCount >= 2) {
      suggestion = OrientationSuggestion.landscape;
    }

    if (suggestion == OrientationSuggestion.none) {
      return const OrientationGuidance(
        suggestedOrientation: OrientationSuggestion.none,
        isMismatch: false,
      );
    }

    // Check if current orientation matches the suggestion
    // Landscape orientations
    final isLandscape = currentOrientation == NativeDeviceOrientation.landscapeLeft ||
        currentOrientation == NativeDeviceOrientation.landscapeRight;
    
    // Portrait orientations
    final isPortrait = currentOrientation == NativeDeviceOrientation.portraitUp ||
        currentOrientation == NativeDeviceOrientation.portraitDown;

    bool mismatch = false;
    
    if (suggestion == OrientationSuggestion.portrait) {
      // Suggesting portrait, but we're in landscape (or unknown/flat)
      // We only flag mismatch if we are SURE we're in landscape to avoid flickering
      if (isLandscape) {
        mismatch = true;
      }
    } else if (suggestion == OrientationSuggestion.landscape) {
      // Suggesting landscape, but we're in portrait (or unknown/flat)
      // We only flag mismatch if we are SURE we're in portrait
      if (isPortrait) {
        mismatch = true;
      }
    }

    return OrientationGuidance(
      suggestedOrientation: suggestion,
      isMismatch: mismatch,
    );
  }
}
