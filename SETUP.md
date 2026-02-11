# 🚀 Pepebot Android - Setup Guide

Complete setup instructions for building the Pepebot Android app.

## Prerequisites

### Required Software

1. **Git**
   ```bash
   git --version  # Should show git version
   ```

2. **Go 1.21+** (for building pepebot binaries)
   ```bash
   go version  # Should show go1.21 or higher
   ```

3. **Android SDK & NDK**
   - Android SDK Platform-Tools
   - NDK (will be auto-downloaded by Gradle)
   - Set `ANDROID_HOME` environment variable

4. **Java 17+**
   ```bash
   java -version  # Should show version 17 or higher
   ```

## Setup Steps

### 1. Clone This Repository

```bash
git clone <this-repo-url> pepebot-android
cd pepebot-android
```

**Note**: The repository does NOT include the `pepebot/` directory. It will be cloned automatically during build.

### 2. Build (No Configuration Needed!)

The build script is pre-configured with the correct pepebot repository:
- **https://github.com/anak10thn/pepebot**

Just run:
```bash
./build.sh
```

No setup required! The script will automatically clone pepebot if it doesn't exist.

### 3. Install on Device

After building, install the APK:

The build script will automatically:
1. Clone https://github.com/anak10thn/pepebot (if not exists)
2. Pull latest changes (if already exists)
3. Build Go binaries for all Android architectures:
   - `pepebot-arm64` (ARM 64-bit - most modern devices)
   - `pepebot-armv7` (ARM 32-bit - older devices)
   - `pepebot-x86_64` (x86 64-bit - emulators)
4. Copy binaries to `termux-app/app/src/main/assets/`
5. Build Android APK

**Option A: Using install script**
```bash
./install.sh
```

**Option B: Manual installation**
```bash
adb install -r termux-app/app/build/outputs/apk/debug/termux-app_apt-android-7-debug_universal.apk
```

## Build Output

After successful build, you'll find APKs in:
```
termux-app/app/build/outputs/apk/debug/
├── termux-app_apt-android-7-debug_universal.apk    # 126MB (all architectures)
├── termux-app_apt-android-7-debug_arm64-v8a.apk    #  51MB (ARM 64-bit only)
├── termux-app_apt-android-7-debug_armeabi-v7a.apk  #  50MB (ARM 32-bit only)
├── termux-app_apt-android-7-debug_x86_64.apk       #  52MB (x86 64-bit only)
└── termux-app_apt-android-7-debug_x86.apk          #  51MB (x86 32-bit only)
```

**Recommendation**: Use the `universal` APK for maximum compatibility, or use architecture-specific APKs for smaller file size.

## Directory Structure

```
pepebot-android/
├── setup.sh              # Interactive setup script
├── build.sh              # Main build script
├── install.sh            # Device installation script
├── .gitignore            # Git configuration (ignores pepebot/)
├── README.md             # Main documentation
├── SETUP.md              # This file
├── logo.png              # App icon source
│
├── pepebot/              # ⚠️ NOT in git (auto-cloned)
│   ├── .git/             # Pepebot's own git history
│   ├── cmd/pepebot/      # Go source code
│   └── ...
│
└── termux-app/           # Modified Termux (no .git)
    ├── .gitignore        # Ignores pepebot-* in assets
    ├── app/
    │   ├── src/main/
    │   │   ├── assets/   # ← Binaries copied here (ignored)
    │   │   │   ├── pepebot-arm64
    │   │   │   ├── pepebot-armv7
    │   │   │   └── pepebot-x86_64
    │   │   └── java/
    │   └── build.gradle
    └── ...
```

## Troubleshooting

### Build fails: "pepebot repository not found"
- Check your internet connection
- The script clones from: https://github.com/anak10thn/pepebot
- Make sure you have access to the repository

### Build fails: "Go not found"
- Install Go: https://golang.org/dl/
- Make sure `go` is in your PATH

### Build fails: "Android SDK not found"
- Install Android Studio or Android SDK command-line tools
- Set `ANDROID_HOME` environment variable:
  ```bash
  export ANDROID_HOME=$HOME/Library/Android/sdk  # macOS
  export ANDROID_HOME=$HOME/Android/Sdk          # Linux
  ```

### Install fails: "No device found"
- Connect Android device via USB
- Enable USB debugging in Developer Options
- Run `adb devices` to verify connection

### App crashes on launch
- Check logcat: `adb logcat | grep -E "(TermuxActivity|PepebotInstaller)"`
- Make sure the correct architecture binary is being used
- Try reinstalling: `./install.sh`

## Updating Pepebot

To update to the latest pepebot version:

```bash
./build.sh  # Automatically pulls latest changes and rebuilds
```

Or manually:
```bash
cd pepebot
git pull
cd ..
./build.sh
```

## Development Workflow

1. **Make changes** to Android code in `termux-app/`
2. **Build**: `./build.sh`
3. **Install**: `./install.sh`
4. **Test** on device
5. **Repeat**

For quick iteration (no pepebot changes):
```bash
cd termux-app
./gradlew assembleDebug
adb install -r app/build/outputs/apk/debug/*.apk
```

## Next Steps

After successful installation:

1. **Launch** the Pepebot app on your device
2. **Wait** for bootstrap extraction (first launch only, ~1-2 minutes)
3. **Tap** ⚙️ Configure to run `pepebot onboard`
4. **Enter** your API keys when prompted
5. **Tap** ▶️ Start Server to launch the gateway
6. **Enjoy** 🐸

## Support

For issues:
- Android app issues: This repository
- Pepebot server issues: Pepebot repository
- Build/setup issues: Create an issue with build logs
