# Roblox Termux Auto-Reconnector

A robust, GUI-based Termux automation tool designed to connect Rooted Android environments directly to a specific Roblox Game ID. It actively monitors the game state and automatically reconnects if the application crashes or drops to the main menu.

## 🚀 Easy Install via Termux

Open **Termux** on your rooted Android device and paste this single command to download and run the setup instantly:

```bash
curl -O https://raw.githubusercontent.com/RiTiKM416/Roblox-reconnector/main/install.sh && bash install.sh
```

*(Note: The setup requires an authentication key provided by the developer. Root access `su` must be granted when prompted by your emulator/device).*

## 🌟 Key Features

*   **Interactive Terminal GUI:** A clean, colored menu interface to input and manage your target Game ID.
*   **Persistent Configuration:** Automatically saves your last used Game ID so you don't have to enter it every time.
*   **Automated Crash Recovery:** Intelligently detects if Roblox crashes or drops you back to the lobby, force-closes the app, and reconnects automatically.
*   **Background Optimization:** Uses a throttled testing loop that minimizes CPU/RAM usage to prevent Termux from crashing during long sessions.
*   **Google Sign-In Bypass:** Detects and automatically dismisses the annoying Google Play Services Sign-In overlay if it tries to intercept the launch.
*   **Pause & Resume Control:** Type `Stop` at any time to freeze the monitor. You can easily access the `Menu` to change the Game ID mid-session.
*   **Live Metrics:** Displays real-time tracking of your active connection time and the current Game ID you are locked into.

## 🛠️ Requirements
*   Android Device or Emulator (e.g., LDPlayer, MuMu)
*   **Root Permissions** (Magisk/SuperSU)
*   [Termux](https://f-droid.org/en/packages/com.termux/) installed
