<div align="center">

# GPhotos-Unlimited Emulator Setup

**Rooted Android emulator with unlimited Google Photos backup — no Android Studio required**

![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20macOS%20%7C%20Linux-blue)
![Android](https://img.shields.io/badge/Android-16%20(API%2036)-green)
![Magisk](https://img.shields.io/badge/Magisk-30.6-important)
![Verified](https://img.shields.io/badge/verified-2026--11--14-success)

</div>

---

This guide gives you, on **any machine (Windows / macOS / Linux)**:

1. A Magisk-rooted Android emulator (Android 16 / API 36, x86_64)
2. The **GPhotos-Unlimited** Magisk module installed on it — this replaces Google Photos with
   a bundled build that is detached from the Play Store and spoofs a Pixel device so Google's
   backend treats the account as Pixel-eligible
3. A **verified test** proving whether "unlimited original-quality backup" actually works for
   your Google account (UI screens alone prove nothing)

## Table of contents

**Beginner track — copy-paste, in order:**

- [Step 0 — Check your machine](#step-0--check-your-machine)
- [Step 1 — Install the Android SDK tools (no Android Studio)](#step-1--install-the-android-sdk-tools-no-android-studio)
- [Step 2 — Create the emulator (AVD)](#step-2--create-the-emulator-avd)
- [Step 3 — Boot the emulator](#step-3--boot-the-emulator)
- [Step 4 — Root it with Magisk (rootAVD)](#step-4--root-it-with-magisk-rootavd)
- [Step 5 — Cold boot + verify Magisk](#step-5--cold-boot--verify-magisk)
- [Step 6 — Download the GPhotos-Unlimited module](#step-6--download-the-gphotos-unlimited-module)
- [Step 7 — Install the module](#step-7--install-the-module)
- [Step 8 — Verify Google Photos was replaced](#step-8--verify-google-photos-was-replaced)
- [Step 9 — Sign in + the real upload test](#step-9--sign-in--the-real-upload-test)
- [Step 10 — Sync your photos from the PC](#step-10--sync-your-photos-from-the-pc)

**Advanced / reference:**

- [How it works under the hood](#how-it-works-under-the-hood)
- [Alternative module: Rev4N1/GPhotosUnlimited (Zygisk)](#alternative-module-rev4n1gphotosunlimited-zygisk-based)
- [Advanced options](#advanced-options)
- [Troubleshooting](#troubleshooting-reference-run-gotchas)
- [Restore / recovery](#restore--recovery)
- [Repository layout](#repository-layout)
- [Agent checklist (automated execution)](#agent-checklist-automated-execution)

> [!WARNING]
> **Verify every release yourself.** Do not blindly reuse versions. Download only from the
> official GitHub repositories listed below. Never use third-party mirrors.

---

# Beginner track

Follow the steps **in order**. Every command is copy-paste ready. One note on placeholders:
everything below uses the AVD name `photos-avd` and the emulator serial `emulator-5554` —
these are fixed values so the steps work when exactly one emulator runs. Change them only if
you know what you're doing (see Advanced).

## Step 0 — Check your machine

You need:

| Requirement | Notes |
|---|---|
| ~10 GB free disk | System image (~5 GB) + AVD data |
| `adb` in PATH | `adb version` must print a version (you'll set this up in Step 1) |
| Internet | for downloads |

Already have Android Studio? Skip to [Step 2](#step-2--create-the-emulator-avd) — your SDK is
already installed.

## Step 1 — Install the Android SDK tools (no Android Studio)

You only need three command-line tools: `adb`, `avdmanager`, `emulator`. No IDE.

**1.1 — Download the Command line tools only zip:**
<https://developer.android.com/studio#command-line-tools-only> (bottom of the page).

**1.2 — Unzip it so the layout is `<SDK>/cmdline-tools/latest/bin`.**
The zip nests one level deeper — move the inner folder up so that `<SDK>\cmdline-tools\latest\bin\sdkmanager.bat` (Windows) or `<SDK>/cmdline-tools/latest/bin/sdkmanager` (macOS/Linux) exists.

> [!TIP]
> Pick a simple SDK path: Windows → `C:\Android\Sdk`, macOS/Linux → `~/Android/Sdk`.

**1.3 — Set `ANDROID_HOME` permanently:**

Windows (PowerShell, then restart the terminal):

```powershell
[Environment]::SetEnvironmentVariable("ANDROID_HOME", "C:\Android\Sdk", "User")
```

macOS/Linux (add to `~/.bashrc` or `~/.zshrc`, then restart the terminal):

```bash
export ANDROID_HOME="$HOME/Android/Sdk"
export PATH="$PATH:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator"
```

**1.4 — Install the required packages** (from `<SDK>/cmdline-tools/latest/bin`):

Windows (PowerShell):

```powershell
cd $env:ANDROID_HOME\cmdline-tools\latest\bin
.\sdkmanager.bat "platform-tools" "emulator"
.\sdkmanager.bat "system-images;android-36.1;google_apis;x86_64"
.\sdkmanager.bat --licenses   # answer y to everything
```

macOS/Linux:

```bash
cd "$ANDROID_HOME/cmdline-tools/latest/bin"
./sdkmanager "platform-tools" "emulator"
./sdkmanager "system-images;android-36.1;google_apis;x86_64"
./sdkmanager --licenses   # answer y to everything
```

**1.5 — Verify:**

```bash
adb version
emulator -version
```

Both must print versions. If `adb` is not found, add `<SDK>\platform-tools` and
`<SDK>\emulator` to PATH and restart the terminal.

**1.6 — Hardware acceleration (one-time):**

- **Windows:**

  ```powershell
  cd $env:ANDROID_HOME\cmdline-tools\latest\bin
  .\sdkmanager.bat "extras;google;Android_Emulator_Hypervisor_Driver"
  # then run the installer it placed in $env:ANDROID_HOME\extras\google\Android_Emulator_Hypervisor_Driver\silent_install.bat
  ```

- **macOS:** built-in (Hypervisor.framework), nothing to do.
- **Linux:** KVM required — `sudo apt install qemu-kvm`, add your user to the `kvm` group,
  log out/in.

## Step 2 — Create the emulator (AVD)

Choose **Google APIs** images (Play Store images are `user` type and behave differently).

```bash
avdmanager create avd -n photos-avd -d pixel_10_pro_xl -k "system-images;android-36.1;google_apis;x86_64"
```

(macOS/Linux may need the full path: `$ANDROID_HOME/cmdline-tools/latest/bin/avdmanager`.)

> [!NOTE]
> The verified reference machine used the `ps16k` (16 KB page size) image variant instead.
> That path needs a patched rootAVD script — see
> [Advanced options → ps16k patch](#advanced-options). Start with the plain `google_apis`
> image above unless you know why you need `ps16k`.

## Step 3 — Boot the emulator

```bash
emulator -avd photos-avd -no-snapshot-load
```

Keep this window open (or add `&` on macOS/Linux to run it in background). Wait until the
home screen is up, then in a **new** terminal check:

```bash
adb devices
adb -s emulator-5554 shell getprop ro.product.cpu.abi        # expect: x86_64
adb -s emulator-5554 shell getprop ro.build.version.sdk      # expect: 36
adb -s emulator-5554 shell getprop ro.build.type             # expect: userdebug
```

Record the stock ramdisk hash (needed later for recovery):

```bash
# Windows (PowerShell):
(Get-FileHash "$env:ANDROID_HOME\system-images\android-36.1\google_apis\x86_64\ramdisk.img" -Algorithm SHA256).Hash
# macOS/Linux:
sha256sum "$ANDROID_HOME/system-images/android-36.1/google_apis/x86_64/ramdisk.img"
```

Save the printed hash in a text file.

## Step 4 — Root it with Magisk (rootAVD)

Get the ready-made rooting kit from this repo: the folder
[`rootavd-windows-patched/`](rootavd-windows-patched/) contains `rootAVD.bat`, `rootAVD.sh`
and the verified `Magisk.zip` (v30.6). On macOS/Linux you use the same folder's `rootAVD.sh`.

> [!IMPORTANT]
> The emulator must still be **running** (online) for this step.

**Windows — open a terminal in the repo's `rootavd-windows-patched` folder and run:**

```cmd
rootAVD.bat system-images\android-36.1\google_apis\x86_64\ramdisk.img FAKEBOOTIMG
```

> The path after `rootAVD.bat` is **relative to `%ANDROID_HOME%`**. If you created the AVD in
> Step 2 with the plain `google_apis` image, the path above is exactly right.
> (PowerShell users: prefix with `cmd /c` — `cmd /c rootAVD.bat ... FAKEBOOTIMG` — the .bat
> must run under cmd.exe, not PowerShell.)

**macOS/Linux:**

```bash
cd rootavd-windows-patched
./rootAVD.sh system-images/android-36.1/google_apis/x86_64/ramdisk.img FAKEBOOTIMG
```

**Expected result (key lines):**

```text
[+] CLI patch succeeded: /sdcard/Download/magisk_patched-CLI.img
[-] Magisk patched boot image detected
[-] Pull ramdiskpatched4AVD.img into ramdisk.img
[-] Trying to shut down the AVD
```

The AVD shuts down at the end — that is normal. Two backups
(`ramdisk.img.backup`, `kernel-ranchu.backup`) were created next to the system image; keep
them, they are your way back ([Restore / recovery](#restore--recovery)).

> [!CAUTION]
> The patched `ramdisk.img` lives in the **shared SDK system image**, not in the AVD folder.
> Every AVD using the same image is now Magisk-booted. Restore = copy the `.backup` files
> back (see [Restore / recovery](#restore--recovery)).

## Step 5 — Cold boot + verify Magisk

**5.1 — Cold-boot the emulator again (no snapshot):**

```bash
emulator -avd photos-avd -no-snapshot-load
```

Wait for full boot (may take a while the first time).

**5.2 — Verify Magisk. Do NOT continue until all of these pass:**

```bash
adb devices                                              # online
adb -s emulator-5554 shell pm list packages magisk       # package:com.topjohnwu.magisk
adb -s emulator-5554 root                                # "restarting adbd as root"
adb -s emulator-5554 shell "su -c id"
# expect: uid=0(root) ... context=u:r:magisk:s0
adb -s emulator-5554 shell "su -c 'magisk -v'"           # expect: 30.6:MAGISKSU
adb -s emulator-5554 shell "ps -A" | grep magisk         # magiskd running
```

Also open the Magisk app once on the emulator — the Home card must show
`Installed 30.6 (30600)`, `Ramdisk: Yes`. Do **not** tap "Update" (31.x is unverified for
this flow).

> [!NOTE]
> If `su -c` says `Permission denied`: MagiskSU policy rejects the shell user. Grant it via
> the Magisk app (Superuser tab) or write the policy DB:

```bash
adb -s emulator-5554 root
adb -s emulator-5554 shell "magisk --sqlite 'INSERT OR REPLACE INTO policies (uid, policy, until) VALUES(2000, 2, 0)'"
```

If magisk CLI reports `Cannot connect to daemon`, magiskd is dead — reboot the AVD and retry.

## Step 6 — Download the GPhotos-Unlimited module

Pick the ZIP for **your** emulator ABI — on x86_64 emulators (default) that is the `x86_64`
asset:

```bash
curl -L -o GPhotos-Unlimited-M-x86_64-MehediHJoy.zip \
  https://github.com/mehedihjoy0/GPhotos-Unlimited/releases/download/v5.0.0/GPhotos-Unlimited-M-x86_64-MehediHJoy.zip
```

(No `curl`? Open the URL in a browser: the direct download link is
`https://github.com/mehedihjoy0/GPhotos-Unlimited/releases/download/v5.0.0/GPhotos-Unlimited-M-x86_64-MehediHJoy.zip`.)

What the installer will do — **read before installing**:

- uninstall the stock Google Photos APK
- install its own bundled Photos 7.24.0 APK
- run `pm clear` on Photos → **Photos app data and sign-in are wiped** (local photos in
  `/sdcard` are untouched)
- detach Photos from Play Store auto-updates
- bind-mount the module APK over `/product/app/Photos`

> [!IMPORTANT]
> **Approval gate:** if this device already has a signed-in Google account or Photos app
> data you care about, stop and decide now — you will lose the app-level sign-in. SD-card
> media is safe.

## Step 7 — Install the module

```bash
adb -s emulator-5554 push GPhotos-Unlimited-M-x86_64-MehediHJoy.zip /data/local/tmp/gphotos-module.zip
adb -s emulator-5554 root
adb -s emulator-5554 shell "magisk --install-module /data/local/tmp/gphotos-module.zip"
adb -s emulator-5554 reboot
```

Expected output: architecture check (`x86_64`), "Extracting Module Files", "Setting
permissions", "Done".

**Quirk:** after CLI install, stray `module.prop` + `update` files may appear directly under
`/data/adb/modules/`. Harmless — remove them:

```bash
adb -s emulator-5554 root
adb -s emulator-5554 shell "rm -f /data/adb/modules/module.prop /data/adb/modules/update"
```

Wait for the reboot to finish, then continue.

## Step 8 — Verify Google Photos was replaced

```bash
# 1. module dir exists and is enabled (no "disable"/"remove" marker files)
adb -s emulator-5554 root
adb -s emulator-5554 shell "ls /data/adb/modules/gphotos-unlimited/"

# 2. Magisk bind-mounts are live
adb -s emulator-5554 shell "grep -i photos /proc/mounts"
# expect: magisk /product/app/Photos tmpfs ro

# 3. Photos is the module's version
adb -s emulator-5554 shell "dumpsys package com.google.android.apps.photos | grep -E 'versionName|versionCode='"
# expect: versionCode=49953386  versionName=7.24.0.747539053

# 4. module service script ran without errors
adb -s emulator-5554 shell "logcat -d -s Magisk:* | tail -20"
# expect: "gphotos-unlimited: exec [service.sh]" and no crash afterwards
```

Launch Photos once (it must not crash), grant the media permission dialog ("Allow all"):

```bash
adb -s emulator-5554 shell monkey -p com.google.android.apps.photos -c android.intent.category.LAUNCHER 1
```

## Step 9 — Sign in + the real upload test

**9.1 — Sign in (human-only step).**
The emulator has no Google account. Sign in yourself: Settings → Accounts → Add account →
Google, or from the Photos prompt. Never automate credentials. 2FA needs you.

**9.2 — Check backup quality options (eligibility, not proof):**

- Photos → Settings → Backup → verify **Backup is ON**
- Photos → Settings → Backup → **Backup quality**: **Original quality** should now be
  selectable. This is *eligibility* — not proof of unlimited.

**9.3 — Upload test (the real proof).**
Never upload private photos. Generate a test image, push it, measure storage before/after:

Windows (PowerShell — generate 800x600 test JPG):

```powershell
Add-Type -AssemblyName System.Drawing
$bmp = New-Object System.Drawing.Bitmap(800,600)
$g   = [System.Drawing.Graphics]::FromImage($bmp)
$g.Clear([System.Drawing.Color]::FromArgb(52,152,219))
$g.DrawString("GPhotos-Test $(Get-Date -f 'yyyy-MM-dd HH:mm')",
              (New-Object System.Drawing.Font('Arial',48)),
              [System.Drawing.Brushes]::White, 80, 260)
$bmp.Save("$PWD\gphotos-test.jpg",[System.Drawing.Imaging.ImageFormat]::Jpeg)
```

Push + upload:

```bash
# BEFORE: note account storage from one.google.com/storage
adb -s emulator-5554 shell mkdir -p /sdcard/DCIM/Camera
adb -s emulator-5554 push gphotos-test.jpg /sdcard/DCIM/Camera/
# force a media rescan:
adb -s emulator-5554 shell "am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d file:///sdcard/DCIM/Camera/gphotos-test.jpg"
# open Photos, wait for backup to finish, then:
adb -s emulator-5554 shell "logcat -d | grep -iE 'upload|backup' | grep -i photos | tail -30"
# AFTER: re-check one.google.com/storage
```

**Interpretation:**

| Observation | Meaning |
|---|---|
| Storage used does NOT grow after the upload | Unlimited claim **confirmed for this account** |
| "Original quality" selectable but storage grows | Module installed fine, but Google still counts it — UI eligibility ≠ unlimited |
| Photos counts the upload under a quota | Module spoof insufficient for this account |

**9.4 — What NOT to do after this:**

- Do not install/update Google Photos from Play Store (Play is detached, but don't fight it).
- Do not clear Play Store data (`com.android.vending`) — that removes the detach state.
- Do not wipe Photos data after testing (would sign the account out).

## Step 10 — Sync your photos from the PC

A host folder feeds the emulator's camera directory. Default pair:

```text
host  : <USER>\Documents\Gphotos          (create it if it doesn't exist)
device: /sdcard/DCIM/Camera
```

**Windows (PowerShell):**

```powershell
$src = "$env:USERPROFILE\Documents\Gphotos"
adb -s emulator-5554 shell mkdir -p /sdcard/DCIM/Camera
adb -s emulator-5554 push "$src\*" /sdcard/DCIM/Camera/
```

**macOS/Linux:**

```bash
src="$HOME/Documents/Gphotos"
adb -s emulator-5554 shell mkdir -p /sdcard/DCIM/Camera
adb push "$src"/*.jpg /sdcard/DCIM/Camera/
```

Run it whenever new photos should land on the emulator. Photos picks up new media
automatically (media scanner). **Never** move/delete the host originals — `adb push` is
copy-only.

> [!TIP]
> **Setup complete.** Day-to-day you only need Step 10. If anything breaks, go to
> [Troubleshooting](#troubleshooting-reference-run-gotchas).

---

# Advanced / reference

## How it works under the hood

1. **rootAVD** (upstream: `gitlab.com/newbit/rootAVD`, maintained mirrors on GitHub) patches
   the AVD system image's `ramdisk.img` by injecting Magisk's `init`/`magisk.xz`/`stub.xz`
   into the ramdisk cpio (the "FAKEBOOTIMG" flow). The originals are automatically saved as
   `ramdisk.img.backup` / `kernel-ranchu.backup` **in the same system-image directory**.
2. The **GPhotos-Unlimited** module replaces the Photos APK, clears its app data, runs a
   `gphotos-detach` binary so Play Store never auto-updates Photos, and bind-mounts the
   module APK over the system path (`/product/app/Photos`).
3. The claim "unlimited original-quality backup" is only true if the **Google account on the
   device is treated as Pixel-eligible by Google's backend**. The module spoofs device
   properties; whether the backend accepts it must be **tested with a real upload** (Step 9.3).
   UI showing "Original quality" is NOT proof.

**Known limitations (from the verified reference run — Windows 11, Pixel_10_Pro_XL,
`system-images;android-36.1;google_apis_ps16k;x86_64`, Magisk 30.6, module v5.0.0):**

- Bundled Photos 7.24.0 is from Apr 2025 and will age; Google may eventually require newer
  versions for some features. Never update it from Play Store (module detaches it anyway).
- The module ZIP contains a precompiled binary (`system/bin/gphotos-detach`, ~1.1 MB). It is a
  compiled blob — audit risk accepted knowingly. It only interacts with the Play Store package
  manager to detach Photos from auto-updates.
- `adb root` (userdebug emulator) and Magisk's `su` are **two different roots**. ADB root is
  not Magisk. Verify both.

## Alternative module: Rev4N1/GPhotosUnlimited (Zygisk-based)

A second, more popular implementation exists:
<https://github.com/Rev4N1/GPhotosUnlimited> (GPL-3.0, adapted from osm0sis's Play
Integrity Fork). It works completely differently:

| | mehedihjoy0/GPhotos-Unlimited (this guide) | Rev4N1/GPhotosUnlimited |
|---|---|---|
| Mechanism | Replaces the Photos APK with a bundled old build (7.24) + bind-mount + Play-detach | Zygisk module spoofs `android.os.Build` fields, system properties, and `PackageManager.hasSystemFeature()` **inside the Photos process only** |
| Photos version | Locked to bundled 7.24 (Apr 2025), never update | Your own Photos, stays updatable |
| Zygisk | Not needed | **Required** (Magisk ≥ 27 with Zygisk enabled) |
| ABI support | x86_64 fine (v5.0.0) | **v5 DROPPED x86/x86_64** (ShadowHook switch) — use **v4** on x86_64 emulators |
| Install size | ~85 MB (contains Photos APK) | ~263 KB |

> [!CAUTION]
> **Choose ONE module. Never both.** Both target the Photos process; they conflict.

To switch from mehedihjoy0 to Rev4N1:

```bash
adb -s emulator-5554 root
adb -s emulator-5554 shell "rm -rf /data/adb/modules/gphotos-unlimited"
adb -s emulator-5554 reboot
```

After reboot the stock/any Photos APK is active again (the mehedihjoy0 bind-mounts vanish).
The Rev4N1 module does NOT need to reinstall Photos — keep the newest Photos you can get.

**Requirements:** Magisk with **Zygisk enabled** (Magisk app Home card: `Zygisk: Yes`).
KernelSU/APatch users need Zygisk Next/ReZygisk/NeoZygisk. Working Google Play Services + a
signed-in Google account.

**Download (x86_64 → v4 only!):**

```bash
curl -L -o GPhotosUnlimited-v4.zip \
  https://github.com/Rev4N1/GPhotosUnlimited/releases/download/v4/GPhotosUnlimited-v4.zip
```

Upstream publishes a checksum — VERIFY it:

- expected: `sha256 3f8cbc84398f66da7c486df09fe955a4937b87dc3e372e38e0824e46e850e7b4`
- size: 263 KB, released 2026-08-11

(v5, tag `v5`, 2026-09-17, is the latest release but explicitly lost x86/x86_64 support —
do not use it on this emulator. Re-check future releases for restored x86_64 support.)

**Install:**

```bash
adb -s emulator-5554 root
adb -s emulator-5554 push GPhotosUnlimited-v4.zip /data/local/tmp/gphotos-zygisk.zip
adb -s emulator-5554 shell "magisk --install-module /data/local/tmp/gphotos-zygisk.zip"
adb -s emulator-5554 reboot
```

On first install the bundled `autofgp.sh` runs automatically and generates a **random
fingerprint from a random official Pixel / Pixel XL (2016) build** (needs internet;
otherwise the bundled default fingerprint is used). Module directory:
`/data/adb/modules/unlimitedphotos/`.

**Verify (different method — storage tier is no longer reliably shown in Settings →
Backup):**

1. Back up a **new** photo (e.g. the synthetic test image from Step 9.3).
2. Open that photo in Photos, swipe up / tap the ⓘ (details).
3. **Working:** details say the photo does **not** count against your Google Account storage.
4. If it says it counts: clear Photos app data + reboot, back up a new photo, re-check.

Storage-before/after accounting (Step 9.3) is still the honest cross-check.

**Configure / troubleshoot:**

```bash
# regenerate fingerprint manually (root shell):
adb -s emulator-5554 root
adb -s emulator-5554 shell "su -c 'cd /data/adb/modules/unlimitedphotos && sh autofgp.sh'"
# module logs right after boot:
adb -s emulator-5554 shell "logcat | grep 'FGP/'"
# verbose logs: add "verboseLogs": "0|1|2|3|100" to custom.fgp.json ("100" dumps all
# spoofed Build fields/props/features)
```

- **Photos must NOT be on Magisk DenyList** (with Enforce DenyList on) — it interferes; the
  module removes it once per reboot anyway.
- Advanced spoof toggles live in `custom.fgp.json`/`custom.fgp.prop`:
  `spoofBuild` (default 1), `spoofProps` (default 0), `spoofProvider` (default 0),
  `spoofSignature` (default 0), `spoofFeatures` (default 1).
- `custom.app_replace_list.txt` can systemlessly disable conflicting ROM spoof-injection
  apps.

## Advanced options

### Use a ps16k (16 KB page size) system image

16 KB-page-size images need a 16 KB-aligned fake boot header — the stock rootAVD hard-codes
`PAGESIZE=2048` and produces a broken header on those images. The bundled
`rootavd-windows-patched/rootAVD.sh` already contains the fix. In `create_fake_boot_img()`
the fix is:

```sh
# ps16k AVD images need 16K alignment for the fake boot header (qig123/rootAVD2026)
PAGESIZE=2048
if [ -n "$AVDPATHWITHRDFFILE" ] && echo "$AVDPATHWITHRDFFILE" | grep -qi "ps16k"; then
    PAGESIZE=16384
fi
```

If you build your own kit from upstream rootAVD, apply this patch and reference the
`...google_apis_ps16k;x86_64` image instead of the plain `google_apis` one in every command.

### Keep multiple emulators running

The serial `emulator-5554` is just the first emulator's default. With several running, list
them (`adb devices`) and substitute the right serial everywhere. Alternatively pin the serial
when starting: `emulator -avd photos-avd -port 5554`.

### Module integrity checks (mehedihjoy0)

- Archive must contain: `META-INF/com/google/android/update-binary`, `module.prop`,
  `install.sh`, `common/{Photos.apk,detach.txt,post-fs-data.sh,service.sh}`, `apks/base.apk`,
  `apks/split_config.x86_64.apk`, `apks/split_config.xxhdpi.apk`, `system/bin/gphotos-detach`
- `module.prop`: `id=gphotos-unlimited`, `versionCode=49953386`, `updateJson` →
  `raw.githubusercontent.com/mehedihjoy0/GPhotos-Unlimited/x86_64/update.json`
- no checksums are published upstream — verify by (a) downloading only from the official
  release URL and (b) comparing the bundled `base.apk` `versionCode/versionName` via
  `aapt dump badging apks/base.apk` → `versionCode='49953386'`, `compileSdkVersion='36'`,
  `targetSdkVersion='35'`, `minSdk 23`. The module's `module.prop` `versionCode` must equal
  the bundled APK's versionCode (it does — `49953386` — otherwise `service.sh`
  reinstalls/clears data every boot).

### Known rootAVD bugs + workarounds (hit in the reference run)

1. **Interactive Magisk-version menu hangs** when the script runs without a TTY
   (`adb shell sh` in the middle of the flow). The menu's first entry is always
   `local ... (ENTER)` — the bundled ZIP. If non-interactive, the `read -t 10` times out and
   entry 1 (local) is chosen; a version check that fetches from raw.githubusercontent.com may
   still hang first. Fix: guard `CheckAvailableMagisks()` with a non-TTY early-out that sets
   `MAGISKVERCHOOSEN=false` and returns (see `rootavd-windows-patched/rootAVD.sh`).
2. **Windows .bat pulls Magisk.apk into a *file* named `Apps`** instead of an `Apps/` folder,
   so the auto-install step installs nothing. Workaround:

   ```powershell
   Rename-Item .\Apps Magisk.apk          # the file IS the APK
   New-Item -ItemType Directory Apps
   Move-Item .\Magisk.apk .\Apps\Magisk.apk
   adb install -r .\Apps\Magisk.apk
   ```

### Magisk APK pinning

`rootavd-windows-patched/Magisk.zip` is Magisk v30.6 (`MAGISK_VER_CODE=30600`), SHA256
`F1FFC3C9A5614C251BA6BADA308163ACC3C3D844CF01D33F55A8BC151ADC34CE`. The patched
`rootAVD.sh` contains two fixes over upstream (ps16k 16 KB page alignment + non-interactive
early-out); both are documented verbatim in `AI_AGENT.md` Stage 0.5 so any machine can
reproduce them from source.

### Reference hashes from the verified run

- stock `ramdisk.img` (ps16k image) SHA256:
  `40878E4010B45AB23C394534AE6DF97777F29B1568CADA89D8B946CC54E02D21`
- module ZIP `GPhotos-Unlimited-M-x86_64-MehediHJoy.zip` (85,616,210 bytes),
  contains Google Photos base.apk `versionCode=49953386`, `versionName=7.24.0.747539053`

## Troubleshooting (reference-run gotchas)

| Symptom | Cause | Fix |
|---|---|---|
| rootAVD hangs at "Checking available Magisk Versions" | non-TTY menu / version fetch | patched script early-outs to local ZIP (Advanced → rootAVD bugs) |
| Magisk app installed but `/data/adb/magisk` empty at first boot | app completes setup on first launch after patched boot | open the app once; verify with `su -c 'magisk -v'` |
| `su -c` → `Permission denied` / log `su: request rejected (2000)` | MagiskSU policy rejects shell | grant via app, or policies DB insert (Step 5.2 note) |
| `su: unrecognized option '--install-module'` / `--sqlite` | MagiskSU consumes flags | use `adb root` + plain `magisk ...` |
| `magisk` CLI → `Cannot connect to daemon: Connection refused` | magiskd dead | reboot the AVD |
| `pm list packages magisk` empty after rootAVD | Windows .bat `Apps` bug | Advanced → rootAVD bugs #2 |
| Photos reinstalled + data cleared on every boot | module.prop versionCode ≠ bundled APK versionCode | use intact v5.0.0 ZIP (49953386 = 49953386) |
| uiautomator dump fails with `null root node` | screen off / UI not ready | wake screen (`input keyevent KEYCODE_WAKEUP`), retry |
| Screenshot unreadable / corrupted | PowerShell 5.1 mangles binary redirects | capture with `cmd /c "adb exec-out screencap -p > file.png"` |
| GDI+ "Out of memory" on host PNG | corrupt/incomplete PNG | re-capture via cmd redirect (previous row) |

## Restore / recovery

1. **Unroot an AVD's image** (revert Magisk ramdisk):

   ```cmd
   cd rootavd-windows-patched
   rootAVD.bat system-images\android-36.1\google_apis\x86_64\ramdisk.img restore
   ```

   (Restores `ramdisk.img` + `kernel-ranchu` from the `.backup` files; backups are kept.)
   Manual equivalent: copy `ramdisk.img.backup` → `ramdisk.img` in the system-image dir.

2. **Remove only the module** (keep Magisk):

   ```bash
   adb -s emulator-5554 root
   adb -s emulator-5554 shell "rm -rf /data/adb/modules/gphotos-unlimited"
   adb -s emulator-5554 reboot
   ```

   The bind-mount disappears on reboot; stock Photos path is usable again (reinstall via
   system or sideload any APK).

3. **Nuclear**: wipe the AVD (Device Manager → Wipe Data) — the patched ramdisk stays until
   step 1 is done. Full pristine state = step 1 + step 3.

4. Verify restoration: `sha256sum ramdisk.img` must equal the stock hash recorded in Step 3.

## Repository layout

```text
gphotos-unlimited-emulator-setup/   ← repo root
├── README.md                        ← this file
├── DEVELOPER.md                     ← human quick guide + background
├── AI_AGENT.md                      ← agent playbook — SELF-CONTAINED:
│                                       works from the text alone; downloads +
│                                       hash-verifies all assets itself (Stage 0)
├── rootavd-windows-patched/         ← ready-to-use Windows rooting kit (optional;
│   ├── rootAVD.bat                  ←   AI_AGENT.md Stage 0 recreates everything
│   ├── rootAVD.sh                   ←   from pinned upstream sources)
│   └── Magisk.zip                   ← Magisk v30.6 APK renamed to ZIP (verified 30600)
└── (host sync folder, see Step 10 — lives outside the repo)
```

## Agent checklist (automated execution)

Machine-readable order of operations. **Gates** marked ⛔ require the user and must not be
automated away.

```text
[ ] 1  adb devices                       → emulator online
[ ] 2  getprop abi/sdk/build-type        → x86_64 / 36 / userdebug; record fingerprint
[ ] 3  sha256sum ramdisk.img             → record stock hash
[ ] 4  Module release check              → latest tag, correct-ABI asset, script audit
[ ] 5  rootAVD ... FAKEBOOTIMG           → backup + patch + Magisk.apk + shutdown
[ ] 6  Cold boot (-no-snapshot-load)     → sys.boot_completed=1
[ ] 7  pm list packages magisk           → com.topjohnwu.magisk (install .apk if missing)
[ ] 8  adb root; su -c 'magisk -v'       → 30.x:MAGISKSU   ← hard gate
[ ] 9  push module.zip; magisk --install-module → "Done"
[ ] 10 adb reboot                        → boot=1
[ ] 11 /proc/mounts contains photos mounts + /data/adb/modules/gphotos-unlimited exists
[ ] 12 dumpsys photos                    → versionCode=49953386
[ ] 13 launch Photos; tap "Allow all"    → no crash
⛔ 14 USER signs in to Google account (never automate credentials)
[ ] 15 Backup ON + quality options recorded (screenshots)
⛔ 16 USER approves the test upload (never upload private media)
[ ] 17 push synthetic test image → wait for upload → storage before/after delta recorded
[ ] 18 Report: AVD config, Magisk version, module version, Photos version,
        eligibility (UI), measured storage delta, limitations, recovery steps
```

Run-log template:

```text
date / host-os / ANDROID_HOME / avd-name / image-path / abi / sdk
stock ramdisk sha256:
magisk version:
module asset + size + source URL:
photos versionCode before / after:
backup quality options shown:
storage before / after / delta:
outcome: <confirmed-unlimited | eligibility-only | failed>
```

---

<div align="center">

Made with rootAVD + Magisk — see [DEVELOPER.md](DEVELOPER.md) for the human quick guide and
[AI_AGENT.md](AI_AGENT.md) for the agent playbook.

</div>
