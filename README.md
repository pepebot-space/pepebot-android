# 🐸 Pepebot Android

Pepebot Android app - A standalone terminal app with integrated Pepebot server control.

## Project Structure

```
pepebot-android/
├── build.sh              # Build script (clones pepebot + builds binaries + debug APK)
├── build-release.sh      # Build release APK for production
├── install.sh            # Install script for device
├── .gitignore            # Ignores pepebot/ directory and binaries
├── README.md             # This file
├── logo.png              # App icon source
├── pepebot/              # ⚠️ NOT tracked by git (auto-cloned by build.sh)
│   └── cmd/pepebot/      # Pepebot Go source code
└── app/                  # Android app source
    └── src/main/
        ├── assets/       # Pepebot binaries (copied by build.sh)
        └── java/          # Android source code
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
- `https://github.com/pepebot-space/pepebot.git`

This script will:
1. **Clone** pepebot repository (if not exists) or **pull** latest changes
2. **Build** pepebot binaries for all Android architectures (arm64, armv7, x86_64)
3. **Copy** binaries to app assets
4. **Build** the Android APK

### Configuring Release Keys

Before generating a release APK/AAB, you must configure the signing keys. Create a `.env` file in the root project directory:

```env
KEYSTORE_FILE=pepebot-release.jks
KEYSTORE_PASSWORD=your_keystore_password
KEY_ALIAS=your_key_alias
KEY_PASSWORD=your_key_password
```

Ensure your `pepebot-release.jks` keystore file is placed in the root directory alongside the `.env` file. Both `.env` and `*.jks` are ignored by git to prevent accidental secret leaks.

If `.env` is absent, the build script will fallback to the `pepebot-debug.jks` testing signature.

### Release Build

For production release APK:
```bash
./build-release.sh
```

To build an Android App Bundle (.aab) instead:
```bash
./build-release.sh --aab
```

APK output: `app/build/outputs/apk/release/`

### Manual Build

```bash
# 1. Build pepebot binaries
cd pepebot
GOOS=android GOARCH=arm64 CGO_ENABLED=0 go build -o pepebot-arm64 ./cmd/pepebot
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o pepebot-x86_64 ./cmd/pepebot

# 2. Copy to assets
mkdir -p ../app/src/main/assets/
cp pepebot-* ../app/src/main/assets/

# 3. Build Android app
cd ..
./gradlew assembleDebug   # Debug build
# or
./gradlew assembleRelease # Release build
```

## Installation

```bash
# Install debug APK (all architectures)
adb install -r app/build/outputs/apk/debug/pepebot_debug_universal.apk

# Install release APK
adb install -r app/build/outputs/apk/release/pepebot_release_universal.apk
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
- **https://github.com/pepebot-space/pepebot**

Simply run:
```bash
./build.sh        # Debug build
# or
./build-release.sh # Release build
```

The script will:
1. Clone pepebot repository (if not exists)
2. Pull latest changes (if already exists)
3. Build everything

The `pepebot/` directory is ignored by git and maintained separately.

## Automated Release (GitHub Actions)

Release builds are automated via GitHub Actions. To create a release:

1. Create and push a tag:
```bash
git tag v1.0.0
git push origin v1.0.0
```

2. The workflow will automatically:
   - Build the release APK
   - Upload it to the GitHub Release

APK can be downloaded from the Release page on GitHub.

## Development

### Key Files Modified

- `app/src/main/java/com/termux/app/TermuxActivity.java` - Button handlers & command injection
- `app/src/main/java/com/termux/app/PepebotInstaller.java` - Binary installation logic
- `app/src/main/res/layout/activity_termux.xml` - UI layout with control buttons
- `app/build.gradle` - Namespace configuration

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
