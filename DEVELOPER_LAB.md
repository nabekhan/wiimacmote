# Local AMFI Lab: virtual gamepad testing

## Purpose

This target exists so a developer can prototype virtual gamepad output **before** receiving Apple authorization for `com.apple.developer.hid.virtual.device`.

The implementation does not depend on another project's code-signing identity, team, provisioning profile, or entitlement approval. The local pipeline is:

1. Build the app without code signing.
2. Apply an ad-hoc signature (`codesign --sign -`) containing the restricted virtual-HID entitlement.
3. Verify the signature and entitlement.
4. Launch the executable directly so launch/AMFI/IOKit errors remain visible in Terminal.

An ad-hoc signature is not accepted for a restricted entitlement on a normally secured Mac. This workflow is only for a deliberately isolated test Mac whose owner has already relaxed SIP and AMFI enforcement.

WiiMacMote never runs `csrutil`, `bputil`, `nvram`, or any equivalent command. The app and scripts only build, sign, inspect, and launch WiiMacMote.

## One-command build and terminal launch

From the project directory:

```sh
./Scripts/run-developer-lab.sh
```

That command builds the **WiiMacMote Developer Lab** configuration, signs the resulting app ad hoc with `WiiMacMote-DeveloperLab.entitlements`, runs the preflight checks, and launches:

```text
build/DeveloperLabDerivedData/Build/Products/DeveloperLab/WiiMacMote.app/Contents/MacOS/WiiMacMote
```

To launch an already-built product after re-signing it:

```sh
./Scripts/run-developer-lab.sh --no-build
```

No `sudo` is required to build, sign, or launch the app.

## Individual commands

Build, explicitly sign, and inspect:

```sh
./Scripts/build-developer-lab.sh
```

Re-sign an existing app:

```sh
./Scripts/sign-developer-lab.sh \
  build/DeveloperLabDerivedData/Build/Products/DeveloperLab/WiiMacMote.app
```

Run host/signature diagnostics:

```sh
./Scripts/diagnose-developer-lab.sh \
  build/DeveloperLabDerivedData/Build/Products/DeveloperLab/WiiMacMote.app
```

Launch the app binary directly, preserving Terminal output:

```sh
./Scripts/run-developer-lab.sh --no-build -- \
  --enable-virtual-gamepad \
  --profile xbox-series \
  --backend iohid
```

Use `--force` only when the diagnostic script cannot read the boot argument but you have independently verified the isolated lab configuration.

Inspect the embedded entitlement manually:

```sh
codesign -d --entitlements :- \
  build/DeveloperLabDerivedData/Build/Products/DeveloperLab/WiiMacMote.app
```

The output must contain:

```xml
<key>com.apple.developer.hid.virtual.device</key>
<true/>
```

The app banner performs a second, runtime check with `SecTaskCopyValueForEntitlement`. This distinguishes an entitlement present in the source plist from one visible to the running task.

## Existing host-security setup

The local experiment assumes the test Mac owner has already made the security changes needed for ad-hoc restricted-entitlement testing. Disabling SIP alone is not the same as relaxing AMFI.

A commonly used lab configuration includes the boot argument:

```text
amfi_get_out_of_my_way=0x1
```

The included diagnostic script only checks for that token and prints `csrutil status`; it does not set either one. Boot arguments and Startup Security behavior vary by Mac model and macOS release, so use current Apple recovery/security documentation for the specific test machine rather than letting an app automate those changes.

## Runtime status and failure meanings

The orange Developer Lab banner reports two independent signals:

- **Entitlement visible:** the running task can read `com.apple.developer.hid.virtual.device=true` from its effective signing context.
- **AMFI boot-argument hint detected:** `kern.bootargs` contains `amfi_get_out_of_my_way=0x1` or `=1`. This is only a hint; successful virtual-device creation remains the definitive test.

Common results:

| Result | Likely meaning |
|---|---|
| `Killed: 9` or code-signing termination before the window opens | AMFI still rejected the restricted entitlement, or the app was not signed as expected |
| App opens and entitlement status is red | Wrong scheme/product, signature was replaced, or the entitlement is not visible to the task |
| Entitlement is green but `IOHIDUserDeviceCreateWithProperties` returns nil | Host security/TCC/IOKit rejected creation despite the claimed entitlement; inspect unified logs |
| Virtual service appears in IORegistry but not Game Controller/System Settings | macOS controller filtering or an incompatible advertised profile/report protocol |
| Game Controller sees it but a particular game does not | Game/SDL mapping or application-specific filtering |

For launch and AMFI diagnostics in a second Terminal window:

```sh
log stream --style compact \
  --predicate 'process == "WiiMacMote" OR process == "amfid" OR eventMessage CONTAINS[c] "WiiMacMote"'
```

## Recommended first functional test

1. Launch with `./Scripts/run-developer-lab.sh` and confirm the physical Wii Remote path still works with virtual output disabled.
2. Confirm the banner shows the entitlement as visible and no Apple team identifier.
3. Quit, then run `./Scripts/run-developer-lab.sh --no-build -- --enable-virtual-gamepad --profile xbox-series --backend iohid`.
4. Check the app log, IORegistry/raw HID, `GCController`, System Settings → Game Controllers, Steam/SDL, Dolphin, and finally a target game.

The Developer Lab configuration defaults to `IOHIDUserDevice` because that is the path this local AMFI experiment is intended to validate. CoreHID remains available as a separate macOS 15+ comparison backend.

## Recognition ladder

Record each layer independently. Success at one layer does not imply success at the next.

1. `IOHIDUserDeviceCreateWithProperties` or CoreHID activation succeeds.
2. The virtual service appears in IORegistry.
3. A raw HID client sees changing reports.
4. `GCController` sees it.
5. System Settings → Game Controllers shows it.
6. Steam/SDL or Dolphin sees it.
7. The target game accepts the mapping.

## Restoring normal security

When testing is complete, restore the Mac's normal security configuration using the recovery procedure appropriate to its model and macOS release. At minimum, remove the AMFI development boot argument if it was added and re-enable SIP; on Apple silicon, restore Full Security where applicable.

The project intentionally does not provide a button or privileged helper that performs those changes.

## Distribution boundary

This ad-hoc lab product is for local development only. A public signed/notarized build that declares the restricted entitlement still requires an Apple-authorized signing identity and provisioning/entitlement approval. The Standard scheme remains separate and does not declare the restricted entitlement.
