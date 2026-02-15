# PLANS.md - Pepebot Terminal Controller (Hybrid Edition)

## 1. Project Overview

**Goal:** Create a standalone Android application that wraps the [pepebot](https://github.com/pepebot-space/pepebot) golang server.
**Base Code:** Fork of [termux/termux-app](https://github.com/termux/termux-app).
**UX Concept:** **"Hybrid Terminal Interface"**.

* **The Terminal:** Remains visible for logs and interactive configuration.
* **The Controls:** A custom button bar overlay provides quick access to core commands (`onboard`, `gateway`, `stop`) without typing.

## 2. Technical Architecture

* **Package Name:** `com.pepebot.terminal` (Must be refactored from `com.termux`).
* **Core Engine:** `TermuxService` running a Node.js environment.
* **UI:** `TermuxActivity` modified to include a `ControlBar` (LinearLayout) at the bottom.
* **Payload:** A custom bootstrap containing Node.js and the `pepebot` source code.

## 3. Critical Reference (READ THIS FIRST)

**Refactoring the Termux package name is complex.** It involves editing C++, JNI, and Java files with hardcoded paths.
**YOU MUST FOLLOW THE GUIDE BELOW FOR PHASE 1:**

> **Reference Article:** [Building Your Own Termux with a Custom Package Name](https://hongchai.medium.com/building-your-own-termux-with-a-custom-package-name-4b2de0c09fac)
> *Use the strategies in this article to locate and replace strict paths (e.g., `/data/data/com.termux/...`) to `/data/data/com.pepebot.terminal/...`.*

## 4. Implementation Phases

### Phase 1: Package Refactor & Environment (The Hard Part)

**Objective:** successfully rename the package and ensure the app compiles.

1. **Refactor Package:**
* Change `package` in `AndroidManifest.xml` to `com.pepebot.terminal`.
* Update `applicationId` in `build.gradle`.
* **Action:** Apply the "Find and Replace" logic from the **Reference Article** above.
* *Target Strings:* `com.termux` -> `com.pepebot.terminal`.
* *Critical Files:* `TermuxConstants.java`, `termux.c` (JNI), `bootstrap.cpp` (if present).


2. **Bootstrap Creation (The Payload):**
* Create a `bootstrap-arm64.zip` containing:
* Minimal Linux Rootfs (`aarch64`).
* **Node.js Binary:** Pre-patched for Android.
* **Pepebot Repo:** Clone `https://github.com/pepebot-space/pepebot` into `/files/home/pepebot`.
* **Dependencies:** Pre-install `node_modules` (ensure `npm install` is run on an ARM64 environment or cross-compiled).


* **Bin Linking:**
* Create a shell script at `/files/usr/bin/pepebot`:
```bash
#!/bin/sh
exec node /data/data/com.pepebot.terminal/files/home/pepebot/index.js "$@"

```


* *chmod +x* this script.





### Phase 2: UI Customization (The Control Bar)

**Objective:** Add the persistent control buttons to the `TermuxActivity`.

1. **Layout Modification (`activity_termux.xml`):**
* Wrap `TerminalView` in a container (Relative/ConstraintLayout).
* Add a **Horizontal LinearLayout** (The Control Bar) at the bottom.
* **Buttons Required:**
* **[ ⚙️ Configure ]** -> ID: `btn_config` (Color: Blue)
* **[ ▶️ Start Server ]** -> ID: `btn_start` (Color: Green)
* **[ ⏹️ Stop ]** -> ID: `btn_stop` (Color: Red)




2. **Styling:**
* Ensure the Control Bar does not overlap the last line of the Terminal. Adjust `TerminalView` margins or padding.
* Ensure the Soft Keyboard can still push the UI up when typing is needed (during configuration).



### Phase 3: Command Logic & Interaction

**Objective:** Wire buttons to inject commands into the active terminal session.

In `TermuxActivity.java`:

1. **"Configure" Button Logic:**
* **Action:** Check if a session exists.
* **Command:** Inject string `pepebot onboard\n`.
* **UX:** Focus the terminal so the keyboard appears (user needs to type API keys).


2. **"Start Server" Button Logic:**
* **Action:** Check if a session exists.
* **Command:** Inject string `pepebot gateway\n`.
* **UX:** Acquire `WakeLock` to keep CPU running.


3. **"Stop" Button Logic:**
* **Command:** Inject `CTRL+C` (Signal: `\u0003`).
* **UX:** Release `WakeLock`.



### Phase 4: Lifecycle & User Experience

1. **Auto-Welcome:**
* Modify the `motd` (Message of the Day) or the default shell startup script.
* Clear the screen and print: *"Welcome to Pepebot! Press 'Configure' to set up, or 'Start Server' to run."*


2. **Permission Handling:**
* Ensure `FOREGROUND_SERVICE` and `WAKE_LOCK` permissions are requested and granted.


3. **Clean Up:**
* Remove the "Drawer" (left side menu) if possible, or strip it of non-essential Termux features (Help, Style, etc.) to focus on Pepebot.



## 5. Verification Checklist

1. [ ] App installs as `com.pepebot.terminal`.
2. [ ] Bootstrap extracts correctly on first launch.
3. [ ] Typing `pepebot` manually in the terminal works.
4. [ ] Clicking "Configure" starts the onboarding wizard.
5. [ ] Clicking "Start Server" runs the gateway and logs appear.
6. [ ] Clicking "Stop" kills the process cleanly.