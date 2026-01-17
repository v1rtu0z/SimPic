import 'package:flutter/material.dart';
import '../models/app_settings.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListenableBuilder(
        listenable: appSettings,
        builder: (context, child) {
          return ListView(
            children: [
              _buildSectionHeader('BACK CAMERA'),
              _buildBackCameraToggles(),
              const Divider(height: 32),
              _buildSectionHeader('FRONT CAMERA (SELFIE)'),
              _buildFrontCameraToggles(),
              const SizedBox(height: 32),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.blueAccent, // Use a clearer color than Theme primary if it's too dark
          fontWeight: FontWeight.bold,
          fontSize: 12,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildBackCameraToggles() {
    final faceEnabled = appSettings.isFaceDetectionSet;
    return Column(
      children: [
        SwitchListTile(
          title: const Text('Face Detection'),
          subtitle: const Text('Enable AI face detection and coaching'),
          value: faceEnabled,
          onChanged: (value) => appSettings.faceDetectionEnabled = value,
        ),
        _buildIndentedToggle(
          title: 'Auto-Shutter',
          subtitle: 'Take photo automatically when perfect',
          value: appSettings.isAutoShutterSet,
          enabled: faceEnabled,
          onChanged: (value) => appSettings.autoShutterEnabled = value,
        ),
        _buildIndentedToggle(
          title: 'Distance Coaching',
          subtitle: 'Show guidance for subject distance',
          value: appSettings.isDistanceCoachingSet,
          enabled: faceEnabled,
          onChanged: (value) => appSettings.distanceCoachingEnabled = value,
        ),
        _buildIndentedToggle(
          title: 'Composition Grid',
          subtitle: 'Show rule of thirds grid and guidance',
          value: appSettings.isCompositionGridSet,
          enabled: faceEnabled,
          onChanged: (value) => appSettings.compositionGridEnabled = value,
        ),
        _buildIndentedToggle(
          title: 'Orientation Suggestion',
          subtitle: 'Suggest landscape or portrait mode',
          value: appSettings.isOrientationSuggestionSet,
          enabled: faceEnabled,
          onChanged: (value) => appSettings.orientationSuggestionEnabled = value,
        ),
      ],
    );
  }

  Widget _buildFrontCameraToggles() {
    final faceEnabled = appSettings.isFrontFaceDetectionSet;
    return Column(
      children: [
        SwitchListTile(
          title: const Text('Face Detection'),
          subtitle: const Text('Enable AI face detection and coaching'),
          value: faceEnabled,
          onChanged: (value) => appSettings.frontFaceDetectionEnabled = value,
        ),
        _buildIndentedToggle(
          title: 'Auto-Shutter',
          subtitle: 'Take photo automatically when perfect',
          value: appSettings.isFrontAutoShutterSet,
          enabled: faceEnabled,
          onChanged: (value) => appSettings.frontAutoShutterEnabled = value,
        ),
        _buildIndentedToggle(
          title: 'Distance Coaching',
          subtitle: 'Show guidance for subject distance',
          value: appSettings.isFrontDistanceCoachingSet,
          enabled: faceEnabled,
          onChanged: (value) => appSettings.frontDistanceCoachingEnabled = value,
        ),
        _buildIndentedToggle(
          title: 'Composition Grid',
          subtitle: 'Show rule of thirds grid and guidance',
          value: appSettings.isFrontCompositionGridSet,
          enabled: faceEnabled,
          onChanged: (value) => appSettings.frontCompositionGridEnabled = value,
        ),
        _buildIndentedToggle(
          title: 'Orientation Suggestion',
          subtitle: 'Suggest landscape or portrait mode',
          value: appSettings.isFrontOrientationSuggestionSet,
          enabled: faceEnabled,
          onChanged: (value) => appSettings.frontOrientationSuggestionEnabled = value,
        ),
      ],
    );
  }

  Widget _buildIndentedToggle({
    required String title,
    required String subtitle,
    required bool value,
    required bool enabled,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 16.0),
      child: SwitchListTile(
        title: Text(
          title,
          style: TextStyle(color: enabled ? Colors.white : Colors.white38),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(color: enabled ? Colors.white70 : Colors.white30),
        ),
        value: value,
        onChanged: enabled ? onChanged : null,
      ),
    );
  }
}
