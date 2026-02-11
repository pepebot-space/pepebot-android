# 🐸 Pepebot Android

Pepebot Android app - A standalone terminal app with integrated Pepebot server control.

## Project Structure

```
pepebot-android/
├── build.sh              # Build script (clones pepebot + builds binaries + APK)
├── install.sh            # Install script for device
├── .gitignore            # Ignores pepebot/ directory and binaries
├── README.md             # This file
├── logo.png              # App icon source
├── pepebot/              # ⚠️ NOT tracked by git (auto-cloned by build.sh)
│   └── cmd/pepebot/      # Pepebot Go source code
└── termux-app/           # Modified Termux app (standalone)
    ├── .gitignore        # Ignores pepebot binaries in assets
    ├── app/
    │   └── src/main/
    │       ├── assets/   # Pepebot binaries (copied by build.sh)
    │       └── java/     # Android source code
    └── build.gradle
```

**Note**: The `pepebot/` directory is NOT included in this repository. It will be automatically cloned by `build.sh` from the separate pepebot repository.

## Features

- **Package Name**: `com.pepebot.terminal`
- **App Name**: Pepebot
- **Custom UI**: 3 control buttons (⚙️ Configure, ▶️ Start Server, ⏹️ Stop)
- **Bundled Binary**: Automatically installs pepebot binary on first run
- **Architecture Support**: arm64, armv7, x86_64
- **Wakelock**: Keeps server running when screen is off

## Building

### Prerequisites

- Go 1.21+ (for building pepebot binaries)
- Android SDK & NDK
- Java 17+
- Gradle (wrapper included)
- Git

### Quick Start

Just run the build script - it will automatically clone pepebot and build everything:

```bash
./build.sh  # Clones pepebot + builds binaries + builds APK
```

The build script is pre-configured with the correct pepebot repository:
- `https://github.com/anak10thn/pepebot.git`

This script will:
1. **Clone** pepebot repository (if not exists) or **pull** latest changes
2. **Build** pepebot binaries for all Android architectures (arm64, armv7, x86_64)
3. **Copy** binaries to termux-app assets
4. **Build** the Android APK

### Manual Build

```bash
# 1. Build pepebot binaries
cd pepebot
GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -o pepebot-arm64 ./cmd/pepebot
GOOS=linux GOARCH=arm GOARM=7 CGO_ENABLED=0 go build -o pepebot-armv7 ./cmd/pepebot
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o pepebot-x86_64 ./cmd/pepebot

# 2. Copy to assets
cp pepebot-* ../termux-app/app/src/main/assets/

# 3. Build Android app
cd ../termux-app
./gradlew assembleDebug
```

## Installation

```bash
# Install universal APK (works on all architectures)
adb install -r termux-app/app/build/outputs/apk/debug/termux-app_apt-android-7-debug_universal.apk

# Or install architecture-specific APK for smaller size
adb install -r termux-app/app/build/outputs/apk/debug/termux-app_apt-android-7-debug_arm64-v8a.apk
```

## Usage

1. **First Launch**: The app will automatically extract the Termux bootstrap and install the pepebot binary
2. **Configure**: Tap the ⚙️ Configure button to run `pepebot onboard` (sets up API keys)
3. **Start Server**: Tap the ▶️ Start Server button to run `pepebot gateway`
4. **Stop Server**: Tap the ⏹️ Stop button to stop the server (Ctrl+C)

## Control Buttons

| Button | Command | Description |
|--------|---------|-------------|
| ⚙️ Configure | `pepebot onboard` | Interactive configuration wizard |
| ▶️ Start Server | `pepebot gateway` | Starts the pepebot gateway server |
| ⏹️ Stop | Ctrl+C | Stops the running server |

## Architecture

The app uses the Termux architecture with custom modifications:

- **PepebotInstaller.java**: Installs the correct pepebot binary for the device architecture
- **TermuxActivity.java**: Modified with custom control buttons and command injection
- **activity_termux.xml**: Custom UI layout with control bar
- **Assets**: Contains pre-built pepebot binaries for all architectures

## Repository Setup

This repository does NOT include the pepebot Go server source code. The build script will automatically clone it from:
- **https://github.com/anak10thn/pepebot**

Simply run:
```bash
./build.sh
```

The script will:
1. Clone pepebot repository (if not exists)
2. Pull latest changes (if already exists)
3. Build everything

The `pepebot/` directory is ignored by git and maintained separately.

## Development

### Key Files Modified

- `termux-shared/src/main/java/com/termux/shared/termux/TermuxConstants.java` - Package name & app name
- `app/build.gradle` - Namespace configuration
- `app/src/main/res/layout/activity_termux.xml` - UI layout with control buttons
- `app/src/main/java/com/termux/app/TermuxActivity.java` - Button handlers & command injection
- `app/src/main/java/com/termux/app/PepebotInstaller.java` - Binary installation logic

### Updating Pepebot

The build script automatically pulls the latest changes from the pepebot repository:
```bash
./build.sh  # Will automatically: git pull + rebuild binaries + rebuild APK
```

Or manually update:
```bash
cd pepebot
git pull
cd ..
./build.sh
```

## License

- **Termux App**: GPLv3 (original Termux project)
- **Pepebot**: Check pepebot repository for license
- **Modifications**: Custom modifications for Pepebot integration

## Credits

Based on [Termux](https://github.com/termux/termux-app) - A powerful terminal emulator for Android.
