# Auto-Portrait Mode Implementation Plan

## 1. Objective
Automatically detect when the user is composing a portrait shot and enable hardware-level or software-simulated bokeh/portrait effects. This should be seamless, stable, and provide clear user feedback.

## 2. Detection Logic (The "When")
Instead of just face size, we use a multi-factor "Portrait Confidence Score".

### Criteria:
- **Face Count:** Exactly 1 significant face.
- **Face Size:** `boundingBox.height` between 20% and 55% of frame height.
- **Positioning:** Face center must be within the central 60% of the frame (avoid edge cases).
- **Stability:** The face center's movement (delta between frames) must be below a threshold for at least 500ms.
- **Focus:** (If available) Check if the face area is in sharp focus.

### Stability Mechanism (Hysteresis):
- **Activation:** Confidence score must stay at 100% for 15 consecutive frames.
- **Deactivation:** Confidence score must drop below 50% for 20 consecutive frames.
- **Smoothing:** Use a `Tween` or `AnimatedContainer` for UI transitions to prevent "glitchy" feel.

## 3. Implementation Strategy (The "How")

### Phase A: Hardware Integration (CameraX Extensions)
1. **Extension Check:** Use CameraX `ExtensionsManager` to check for `EXTENSION_MODE_BOKEH`.
2. **Dynamic Toggle:** Implement a way to rebind the CameraX UseCases with the Bokeh extension enabled/disabled without restarting the whole camera controller.
3. **Fallback:** If hardware Bokeh is unavailable, consider `EXTENSION_MODE_FACE_RETOUCH`.

### Phase B: Software Fallback (Selfie Segmentation)
1. **ML Kit Integration:** Integrate `google_mlkit_selfie_segmentation`.
2. **Preview Processing:** (If performance allows) Apply a blur filter to the non-person mask in the preview.
3. **Post-Processing:** If preview blur is too heavy, apply the blur only to the saved image after capture.

### Phase C: UI/UX
1. **Indicator:** A polished "PORTRAIT" badge that fades in/out.
2. **Visual Hint:** A subtle "vignette" or "depth-of-field" overlay on the preview when active.
3. **Transition:** Use a 300ms ease-in-out animation for the color and visibility changes.

## 4. Debugging & Iteration Plan (For AI Agents)

### Step 1: Data Collection & Logging
- Implement a `PortraitDebugResult` class that carries:
    - `faceSizeRatio`
    - `distanceFromCenter`
    - `stabilityFactor`
    - `consecutiveFrameCount`
    - `isHardwareExtensionAvailable`
- Print these to `debugPrint` every 30 frames with a unique prefix: `[AUTO_PORTRAIT_DEBUG]`.

### Step 2: Visual Debug Overlay
- Add a `debugMode` toggle in Settings.
- When on, draw:
    - The "Portrait Candidate Zone" (the central box).
    - The face bounding box (Color: Orange if candidate, Green if active).
    - A progress bar showing the "Confidence" (how close it is to activating).

### Step 3: Iteration Loop
1. **Test Case 1:** Hold phone at arm's length (Selfie). Should trigger within 1 sec.
2. **Test Case 2:** Subject 2 meters away. Should NOT trigger.
3. **Test Case 3:** Fast movement. Should deactivate immediately.
4. **Test Case 4:** Two people. Should NOT trigger.
5. **Adjust:** If it flickers, increase the `deactivation` frame count. If it's too slow, decrease `activation` frame count.

## 5. Files to Create/Modify
- `lib/models/portrait_analysis.dart`: New model for the logic.
- `lib/services/camera_service.dart`: Update to handle CameraX Extensions.
- `lib/widgets/portrait_indicator.dart`: New UI component.
- `lib/screens/camera_screen.dart`: Integration point.
