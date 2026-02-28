# WiiMacMote

Use your Nintendo Wiimote as a virtual gamepad on your Mac! 

## Installation

1. **Download the app:**
   [Download WiiMacMote.dmg](https://github.com/gdemontalivet/wiimacmote/raw/main/WiiMacMote.dmg)

2. **Install:**
   - Open the downloaded `WiiMacMote.dmg` file.
   - Drag and drop the `wiimacmote` application into your `/Applications` folder.

3. **Open the app:**
   - Go to your Applications folder and open `wiimacmote`.
   - *Note: Since the app is not signed with an Apple Developer account, macOS may prevent it from opening initially. To fix this, go to **System Settings > Privacy & Security**, scroll down to the Security section, and click **"Open Anyway"** next to the wiimacmote notice.*

4. **Grant Permissions:**
   For WiiMacMote to create a virtual gamepad and connect to your Wiimote, you need to grant it the following permissions when prompted:
   - **Input Monitoring**: Go to **System Settings > Privacy & Security > Input Monitoring** and enable the toggle for `wiimacmote`.
   - **Bluetooth**: Go to **System Settings > Privacy & Security > Bluetooth** and ensure `wiimacmote` is allowed.

5. **Connect your Wiimote:**
   - Launch the app.
   - Press the **SYNC** button on the back of your Wiimote (or buttons 1 and 2 simultaneously) so the LEDs start flashing.
   - Click the **Pair Wiimote** button in the app.
   - Once connected, your Mac will recognize the Wiimote as a standard gamepad!

## How it works
WiiMacMote connects to your Wiimote via Bluetooth and translates its button presses into a virtual HID Gamepad on your Mac. This means you can use your Wiimote to play games, control emulators, or use it anywhere a standard controller is supported!
