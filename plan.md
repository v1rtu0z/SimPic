# AI Photography Coach - Detailed Feature Plan

## Development Order & Priorities

### Phase 1: Foundation (Hours 1-4)
**Goal: Get a working camera app that saves to gallery**

#### Feature 1.1: Basic CameraX Integration
- **Priority: P0 (Must have)**
- **Complexity: Medium**
- Set up CameraX with preview
- Implement capture button
- **Save location: `Environment.DIRECTORY_DCIM + "/Camera"`** or `Environment.DIRECTORY_PICTURES`
- Use MediaStore API (Android 10+) to ensure photos appear immediately in gallery
- Test that photos show up in Google Photos/Gallery app instantly

#### Feature 1.2: Face Detection Setup
- **Priority: P0**
- **Complexity: Low**
- Integrate ML Kit Face Detection
- Set up real-time processing pipeline (analyze every 3-5 frames, not every frame)
- Draw bounding boxes on detected faces (for debugging)

---

### Phase 2: Core Coaching Features (Hours 5-12)
**Goal: Give actionable real-time guidance**

#### Feature 2.1: Distance Coaching
- **Priority: P0 (Highest impact for people photos)**
- **Complexity: Low**
- **Logic:**
  - Calculate face size as % of frame height
  - Optimal range: 25-40% of frame height for portraits
  - Too small (<20%): Show "MOVE CLOSER" with a forward arrow
  - Too large (>50%): Show "STEP BACK" with a backward arrow
  - Good range: Show green checkmark or "Good distance"
- **UI:** Large text overlay at top of screen, color-coded (red/yellow/green)

#### Feature 2.2: Composition Grid & Face Positioning
- **Priority: P0**
- **Complexity: Medium**
- **Logic:**
  - Draw rule of thirds grid (2 vertical, 2 horizontal lines)
  - Calculate "power points" (4 intersections)
  - Measure distance from face center to nearest power point
  - Within 15% of frame dimension = "well positioned"
  - Show directional arrows to guide subject toward nearest power point
- **UI:** 
  - Semi-transparent grid overlay
  - Pulsing circles at power points
  - Arrow overlays (←↑→↓) showing which direction to move camera
  - "Perfect positioning!" when aligned

#### Feature 2.3: Orientation Suggestion
- **Priority: P1**
- **Complexity: Low**
- **Status: ✅ Completed**
- **Logic:**
  - Count faces detected
  - Single face: suggest portrait orientation
  - Multiple faces (2+): suggest landscape orientation
  - If current orientation doesn't match suggestion, show rotation icon
- **UI:** Small rotation icon in corner when orientation mismatch detected

---

### Phase 3: Lighting Intelligence (Hours 13-16)
**Goal: Help avoid harsh shadows and backlit faces**

#### Feature 3.1: Face Exposure Analysis
- **Priority: P0 (Huge quality impact)**
- **Complexity: Medium**
- **Logic:**
  - Sample brightness within face bounding box
  - Sample brightness of surrounding area (halo around face)
  - Calculate ratio
  - **Backlit detection:** Face much darker than background (ratio < 0.6)
  - **Harsh shadow detection:** Significant brightness variance within face region (std dev > threshold)
  - **Good lighting:** Face slightly brighter than background (ratio 1.1-1.3)
- **UI:**
  - "⚠️ Face in shadow - move to brighter area"
  - "☀️ Backlit - turn around or use flash"
  - "✓ Good lighting" (green indicator)

#### Feature 3.2: Auto-exposure Lock on Face
- **Priority: P0**
- **Complexity: Low**
- **Implementation:**
  - When face detected, set camera focus/exposure metering point to face center
  - Lock exposure to keep face properly exposed
  - Visual feedback: yellow square around face when locked
- **Fallback:** If multiple faces, expose for the largest/closest one

---

### Phase 4: Smart Capture Assists (Hours 17-20)
**Goal: Catch the best moment automatically**

#### Feature 4.1: Blink Detection
- **Priority: P1**
- **Complexity: Low (ML Kit provides eye open probability)**
- **Logic:**
  - Check ML Kit's `leftEyeOpenProbability` and `rightEyeOpenProbability`
  - Both eyes open (>0.8): ready to shoot
  - Either eye closed: delay capture or show "Wait - eyes closed"
  - On capture button press: if eyes closed, wait up to 500ms for eyes to open
- **UI:** Small eye icon indicator (open/closed state)

#### Feature 4.2: Framing Score System
- **Priority: P1**
- **Complexity: Medium**
- **Logic - Calculate composite score (0-100):**
  - Distance score (40 points): optimal = 40, too far/close = 0-30
  - Position score (30 points): on power point = 30, off = 0-20
  - Lighting score (30 points): good lighting = 30, backlit/shadow = 0-15
  - **Total score shown as color-coded percentage**
- **UI:** 
  - Large circular progress indicator (like speedometer)
  - Score >80: Green, "Great shot!"
  - Score 60-80: Yellow, "Good"
  - Score <60: Red, "Needs adjustment"
  - Capture button pulses green when score >80

#### Feature 4.3: Auto Portrait Mode Toggle
- **Priority: P1**
- **Complexity: Low**
- **Logic:**
  - When single face detected AND face size >25% of frame
  - Automatically enable portrait mode (background blur)
  - Disable when no face or multiple faces
- **UI:** Portrait mode icon indicator when active

---

### Phase 5: Quality of Life (Hours 21-24)
**Goal: Polish and usability**

#### Feature 5.1: Coaching Overlay Toggle
- **Priority: P1**
- **Complexity: Low**
- Button to hide/show all coaching overlays
- Preserve setting across app sessions
- Useful once you've learned the basics

#### Feature 5.2: Settings Screen
- **Priority: P2**
- **Complexity: Low**
- Adjust sensitivity thresholds
- Toggle individual coaching features on/off
- Choose save location preference

#### Feature 5.3: Quick Review
- **Priority: P2**
- **Complexity: Low**
- Thumbnail preview after capture (bottom corner)
- Tap to view full size with basic metadata
- Swipe to delete if shot is bad

---

## Technical Implementation Notes

### TODO / Known Issues
- **Arrow Visibility**: Guide arrows (currently cyan/blue) should use negative/inverse color of background for better visibility. Blue arrows would be invisible against blue sky backgrounds. Consider using white with dark outline, or dynamically sampling background color and inverting.

### Performance Optimization
- **Face detection frequency:** Process every 3-5 frames (~6-10 fps), not every frame
- **Use InputImage.fromMediaImage** for efficient frame processing
- **Run ML Kit in detector mode**, not streaming mode initially
- **Cache calculations:** Don't recalculate grid positions every frame

### Edge Cases to Handle
1. **No face detected:** Show "No face found - move subject into frame"
2. **Multiple faces:** Primary coaching on largest face, note others detected
3. **Low light:** Suggest flash or move to brighter area
4. **Camera permission denied:** Clear error message with settings link
5. **Storage permission issues:** Handle MediaStore failures gracefully

### Libraries/Dependencies
```
// CameraX
androidx.camera:camera-camera2:1.3.0
androidx.camera:camera-lifecycle:1.3.0
androidx.camera:camera-view:1.3.0

// ML Kit Face Detection
com.google.mlkit:face-detection:16.1.5

// Coroutines for async processing
org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3
```

---

## Success Metrics
After weekend build, you should have:
- ✅ Photos save directly to gallery (visible immediately)
- ✅ Real-time distance coaching
- ✅ Composition guidance with visual feedback
- ✅ Lighting warnings for backlit/shadowed faces
- ✅ Auto-exposure on detected faces
- ✅ Overall framing score to know when to shoot

## Future Enhancements (Post-Weekend)
- Smile detection to catch best expressions
- Group photo mode (ensure everyone visible)
- Golden hour detector (best outdoor lighting times)
- Shot history with score tracking
- Tutorial mode explaining each feature

---

## Recommended Build Order Summary
1. ✅ **Start here:** Basic camera + gallery saving (validate this works first!)
2. ✅ Face detection integration
3. ✅ Distance coaching (biggest quick win)
4. ✅ Face exposure lock (second biggest win)
5. ✅ Composition grid + positioning
6. ✅ Lighting analysis
7. ✅ Framing score system
8. Polish: Blink detection, portrait mode, toggles

This gives you a working, useful app after ~8 hours, with incremental improvements from there. Good luck - this should genuinely help your people photography!