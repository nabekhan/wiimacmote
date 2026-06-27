# Building and validating WiiMacMote

## Build host

Use macOS with Xcode 16 or newer. Xcode 26 is recommended for current macOS; the project keeps an explicit, conventional project structure rather than requiring synchronized-folder features.

## Standard configuration

The Standard configuration targets macOS 14+, keeps Hardened Runtime enabled, and omits the restricted virtual-HID entitlement. It still exposes the same virtual-output UI path so entitlement/signing failures are visible and non-fatal.

In Xcode, open `WiiMacMote.xcodeproj`, select **WiiMacMote**, choose **My Mac**, and build. No development team is stored in the project.

Portable command-line validation and local ad-hoc build signing:

```sh
./Scripts/verify-source.sh
./Scripts/build.sh
```

`build.sh` compiles with Xcode signing disabled, then applies a local ad-hoc signature to the Release product under `build/DerivedData`. A universal signed archive can be created after configuring a signing identity:

```sh
./Scripts/archive-universal.sh
```

If a locally copied ad-hoc app in `/Applications` can open CoreBluetooth but Classic inquiry returns `kIOReturnNotPermitted`, refresh the local signature before launching it again:

```sh
./Scripts/build.sh --sign-installed
```

That flag runs `codesign --force --deep --sign - /Applications/WiiMacMote.app` after the local build. Use it only for local testing; release artifacts should be signed through the normal archive/notarization path.

## Local AMFI Lab configuration

The **WiiMacMote Developer Lab** scheme uses the `DeveloperLab` build configuration. It adds the virtual-HID entitlement, disables Hardened Runtime for the lab product, uses a separate bundle identifier, and defines `DEVELOPER_LAB` for the local-lab warning. The source path is otherwise shared with Standard.

The deterministic command-line path intentionally separates compilation from signing:

```sh
./Scripts/run-developer-lab.sh
```

`build-developer-lab.sh` passes `CODE_SIGNING_ALLOWED=NO`, `CODE_SIGNING_REQUIRED=NO`, and an empty signing identity so Xcode never asks for an Apple team or provisioning profile. It then invokes `sign-developer-lab.sh`, which applies a local ad-hoc signature containing the entitlement, followed by `diagnose-developer-lab.sh`. `run-developer-lab.sh` delegates to `launch-developer-lab.sh`, which executes the bundle binary directly.

To reapply the signature to a built app:

```sh
./Scripts/sign-developer-lab.sh /path/to/WiiMacMote.app
```

Inspect it with:

```sh
codesign -d --entitlements :- /path/to/WiiMacMote.app
```

An ad-hoc signature is not Apple authorization for a restricted entitlement. This product is intended only for an isolated developer Mac whose owner has already relaxed AMFI enforcement. See `DEVELOPER_LAB.md` before launch.

## Build settings

| Setting | Standard | Developer Lab |
|---|---:|---:|
| Deployment target | macOS 14 | macOS 14 |
| CoreHID backend | runtime macOS 15+ | runtime macOS 15+ |
| Hardened Runtime | On | Off |
| App Sandbox | Off | Off |
| Bluetooth entitlement | Yes | Yes |
| Virtual-HID entitlement | No | Yes |
| Signing | Xcode/local or build script ad-hoc `codesign -` | Unsigned Xcode build, then explicit ad-hoc `codesign -` |

CoreHID is weak-linked so the app can still launch on macOS 14. The source is compiled conditionally when the selected SDK contains CoreHID, and every call is guarded by a macOS 15 availability check.

## Validation checklist

1. `Scripts/verify-source.sh` passes.
2. Standard Debug and Release build without source errors.
3. DeveloperLab builds without an Apple team, is explicitly ad-hoc signed, and its signature contains `com.apple.developer.hid.virtual.device`.
4. The Standard signature does not contain that entitlement.
5. Physical Wii Remote pairing, buttons, battery, LEDs, rumble, and motion work with virtual output disabled.
6. The Scan toggle resumes after canceled macOS Bluetooth Connection Request prompts and after benign Classic inquiry completions.
7. Each virtual identity is tested separately through IORegistry/raw HID, Game Controller, System Settings, Steam/SDL, Dolphin, and one target game.
8. Disabling or changing a profile sends a neutral report and removes the prior virtual device.
9. Apple silicon and Intel results are recorded separately.
