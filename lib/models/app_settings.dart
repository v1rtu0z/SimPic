import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings extends ChangeNotifier {
  static const String _keyFaceDetection = 'faceDetectionEnabled';
  static const String _keyAutoShutter = 'autoShutterEnabled';
  static const String _keyDistanceCoaching = 'distanceCoachingEnabled';
  static const String _keyCompositionGrid = 'compositionGridEnabled';
  static const String _keyOrientationSuggestion = 'orientationSuggestionEnabled';

  static const String _keyFrontFaceDetection = 'frontFaceDetectionEnabled';
  static const String _keyFrontAutoShutter = 'frontAutoShutterEnabled';
  static const String _keyFrontDistanceCoaching = 'frontDistanceCoachingEnabled';
  static const String _keyFrontCompositionGrid = 'frontCompositionGridEnabled';
  static const String _keyFrontOrientationSuggestion = 'frontOrientationSuggestionEnabled';

  bool _faceDetectionEnabled = true;
  bool _autoShutterEnabled = true;
  bool _distanceCoachingEnabled = true;
  bool _compositionGridEnabled = true;
  bool _orientationSuggestionEnabled = true;

  bool _frontFaceDetectionEnabled = true;
  bool _frontAutoShutterEnabled = true; // Default to true for selfie
  bool _frontDistanceCoachingEnabled = true;
  bool _frontCompositionGridEnabled = true;
  bool _frontOrientationSuggestionEnabled = true;

  bool _isFrontCamera = false;

  bool get isFrontCamera => _isFrontCamera;

  bool get faceDetectionEnabled => _isFrontCamera ? _frontFaceDetectionEnabled : _faceDetectionEnabled;
  bool get autoShutterEnabled {
    if (_isFrontCamera) {
      return _frontFaceDetectionEnabled && _frontAutoShutterEnabled;
    }
    return _faceDetectionEnabled && _autoShutterEnabled;
  }
  
  bool get distanceCoachingEnabled => faceDetectionEnabled && (_isFrontCamera ? _frontDistanceCoachingEnabled : _distanceCoachingEnabled);
  bool get compositionGridEnabled => faceDetectionEnabled && (_isFrontCamera ? _frontCompositionGridEnabled : _compositionGridEnabled);
  bool get orientationSuggestionEnabled => faceDetectionEnabled && (_isFrontCamera ? _frontOrientationSuggestionEnabled : _orientationSuggestionEnabled);

  // Internal getters for actual state
  bool get isFaceDetectionSet => _faceDetectionEnabled;
  bool get isAutoShutterSet => _autoShutterEnabled;
  bool get isDistanceCoachingSet => _distanceCoachingEnabled;
  bool get isCompositionGridSet => _compositionGridEnabled;
  bool get isOrientationSuggestionSet => _orientationSuggestionEnabled;

  bool get isFrontFaceDetectionSet => _frontFaceDetectionEnabled;
  bool get isFrontAutoShutterSet => _frontAutoShutterEnabled;
  bool get isFrontDistanceCoachingSet => _frontDistanceCoachingEnabled;
  bool get isFrontCompositionGridSet => _frontCompositionGridEnabled;
  bool get isFrontOrientationSuggestionSet => _frontOrientationSuggestionEnabled;

  void setCameraLens(bool isFront) {
    if (_isFrontCamera == isFront) return;
    _isFrontCamera = isFront;
    notifyListeners();
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Back camera
    _faceDetectionEnabled = prefs.getBool(_keyFaceDetection) ?? true;
    _autoShutterEnabled = prefs.getBool(_keyAutoShutter) ?? true;
    _distanceCoachingEnabled = prefs.getBool(_keyDistanceCoaching) ?? true;
    _compositionGridEnabled = prefs.getBool(_keyCompositionGrid) ?? true;
    _orientationSuggestionEnabled = prefs.getBool(_keyOrientationSuggestion) ?? true;

    // Front camera
    _frontFaceDetectionEnabled = prefs.getBool(_keyFrontFaceDetection) ?? true;
    _frontAutoShutterEnabled = prefs.getBool(_keyFrontAutoShutter) ?? true;
    _frontDistanceCoachingEnabled = prefs.getBool(_keyFrontDistanceCoaching) ?? true;
    _frontCompositionGridEnabled = prefs.getBool(_keyFrontCompositionGrid) ?? true;
    _frontOrientationSuggestionEnabled = prefs.getBool(_keyFrontOrientationSuggestion) ?? true;
    
    notifyListeners();
  }

  // Back camera setters
  set faceDetectionEnabled(bool value) {
    if (_faceDetectionEnabled == value) return;
    _faceDetectionEnabled = value;
    _save(_keyFaceDetection, value);
    notifyListeners();
  }

  set autoShutterEnabled(bool value) {
    if (_autoShutterEnabled == value) return;
    _autoShutterEnabled = value;
    _save(_keyAutoShutter, value);
    notifyListeners();
  }

  set distanceCoachingEnabled(bool value) {
    if (_distanceCoachingEnabled == value) return;
    _distanceCoachingEnabled = value;
    _save(_keyDistanceCoaching, value);
    notifyListeners();
  }

  set compositionGridEnabled(bool value) {
    if (_compositionGridEnabled == value) return;
    _compositionGridEnabled = value;
    _save(_keyCompositionGrid, value);
    notifyListeners();
  }

  set orientationSuggestionEnabled(bool value) {
    if (_orientationSuggestionEnabled == value) return;
    _orientationSuggestionEnabled = value;
    _save(_keyOrientationSuggestion, value);
    notifyListeners();
  }

  // Front camera setters
  set frontFaceDetectionEnabled(bool value) {
    if (_frontFaceDetectionEnabled == value) return;
    _frontFaceDetectionEnabled = value;
    _save(_keyFrontFaceDetection, value);
    notifyListeners();
  }

  set frontAutoShutterEnabled(bool value) {
    if (_frontAutoShutterEnabled == value) return;
    _frontAutoShutterEnabled = value;
    _save(_keyFrontAutoShutter, value);
    notifyListeners();
  }

  set frontDistanceCoachingEnabled(bool value) {
    if (_frontDistanceCoachingEnabled == value) return;
    _frontDistanceCoachingEnabled = value;
    _save(_keyFrontDistanceCoaching, value);
    notifyListeners();
  }

  set frontCompositionGridEnabled(bool value) {
    if (_frontCompositionGridEnabled == value) return;
    _frontCompositionGridEnabled = value;
    _save(_keyFrontCompositionGrid, value);
    notifyListeners();
  }

  set frontOrientationSuggestionEnabled(bool value) {
    if (_frontOrientationSuggestionEnabled == value) return;
    _frontOrientationSuggestionEnabled = value;
    _save(_keyFrontOrientationSuggestion, value);
    notifyListeners();
  }

  Future<void> _save(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }
}

final appSettings = AppSettings();
