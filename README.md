# SimPic - AI Photography Coach

SimPic is an AI-powered camera app that provides real-time coaching to help you take better portraits and improve your photography skills.

---

## 🎯 Current Status & Tech Stack

### Phase 1: Foundation (Migration to Vision Camera) 🚧
We are currently migrating from `expo-camera` to `react-native-vision-camera` to enable professional-grade face detection and hardware control required for real-time coaching.

*   **Framework**: React Native (Expo SDK 54)
*   **Camera Engine**: [React Native Vision Camera](https://react-native-vision-camera.com/) (Chosen for performance and ML frame processors)
*   **Target Device**: Android (Physical device via USB)
*   **Dev Workflow**: Development Builds with Hot Reloading (Fast Refresh)

---

## 🛠 Setup & Development Workflow

### 1. Prerequisites (Linux)
Ensure you have the following installed:
*   **Java 21**: `export JAVA_HOME=/usr/lib/jvm/java-1.21.0-openjdk-amd64`
*   **Android SDK**: `export ANDROID_HOME=$HOME/Android/Sdk`
*   **ADB**: Part of `platform-tools`

### 2. Installation
```bash
npm install
```

### 3. Running the App (USB Hot-Reload)
We use **Development Builds** instead of Expo Go to access native camera features.

1.  **Connect your phone** via USB and ensure USB Debugging is on.
2.  **Bridge the port**:
    ```bash
    adb reverse tcp:8081 tcp:8081
    ```
3.  **Start the Dev Server**:
    ```bash
    npm start
    ```
4.  **Run on Android**:
    ```bash
    npm run android
    ```
    *(Note: This installs a custom "SimPic" development app on your phone. Once installed, JS changes will hot-reload instantly.)*

---

## 🗺 Roadmap

### Phase 1: High-Performance Engine (CURRENT)
- [x] Set up Linux-compatible build environment
- [x] Configure Development Build workflow
- [x] Migrate to `react-native-vision-camera`
- [x] Implement manual focus with visual feedback
- [x] Re-enable Face Detection using Vision Camera Frame Processors

### Phase 2: Core Coaching (Next)
- [ ] **Distance Coaching**: Guide the user to move closer or step back based on face size.
- [ ] **Composition Overlay**: Rule of Thirds and Golden Ratio grids.
- [ ] **Face Positioning**: Visual cues to center or offset subjects for better portraits.

### Phase 3: Intelligence
- [ ] **Lighting Analysis**: Detect backlit subjects or harsh shadows.
- [ ] **Smart Capture**: Blink detection and smile-triggered capture.

---

## 📝 Developer Notes
*   **Why Vision Camera?** Expo's built-in face detector is deprecated in SDK 54 and lacks the low-latency performance needed for "real-time" coaching.
*   **Build Issues**: If you see `JAVA_HOME` or `ANDROID_HOME` errors, ensure the exports in step 1 are in your `~/.bashrc`.
*   **Rebuilds**: You only need to run `npm run android` when adding new native libraries. For UI and logic changes, `npm start` is enough.

