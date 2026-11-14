# GPhotos-Unlimited Emulator Setup (`gphotos-unlimited-emulator-setup`)

> Repo name: `gphotos-unlimited-emulator-setup` — this folder IS the repo root.

This guide reproduces, on **any machine (Windows / macOS / Linux)**, a working setup where an
Android Studio emulator (Android 16 / API 36, x86_64) runs **Magisk 30.6** and the
**GPhotos-Unlimited** Magisk module, replacing Google Photos with a bundled build that is
detached from the Play Store.

**Reference implementation** (fully verified end-to-end on 2026-11-14):

- Host: Windows 11, PowerShell 5.1
- AVD: `Pixel_10_Pro_XL`, image `system-images;android-36.1;google_apis_ps16k;x86_64`
- Magisk: **30.6 (30600)** via rootAVD
- Module: **GPhotos-Unlimited v5.0.0** (release tag `v5.0.0`), x86_64 asset
- Google Photos after install: **7.24.0.747539053** (versionCode `49953386`)

> ⚠️ **Verify every release yourself.** Do not blindly reuse versions. Download only from the
> official GitHub repositories listed below. Never use third-party mirrors.

---

## 0. How this works (read first)

1. **rootAVD** (upstream: `gitlab.com/newbit/rootAVD`, maintained mirrors on GitHub) patches the
   AVD system image's `ramdisk.img` by injecting Magisk's `init`/`magisk.xz`/`stub.xz` into the
   ramdisk cpio (the "FAKEBOOTIMG" flow). The originals are automatically saved as
   `ramdisk.img.backup` / `kernel-ranchu.backup` **in the same system-image directory**.
2. **Important side effect:** the `ramdisk.img` lives in the **shared SDK system image**, not in
   the AVD folder. Patching it affects *every* AVD that uses the same image. Restore = copy the
   `.backup` files back (see §12 Recovery).
3. The **GPhotos-Unlimited** module then:
   - uninstalls the stock Google Photos APK,
   - installs its own bundled Photos APK (x86_64 split included in the ZIP),
   - clears the Photos **app data** (`pm clear` — local photos in `/sdcard` are untouched),
   - runs a `gphotos-detach` binary so Play Store never auto-updates Photos,
   - bind-mounts the module APK over the system path (`/product/app/Photos`).
4. The claim "unlimited original-quality backup" is only true if the **Google account on the
   device is treated as Pixel-eligible by Google's backend**. The module spoofs device
   properties; whether the backend accepts it must be **tested with a real upload** (§8.3).
   UI showing "Original quality" is NOT proof.

### Known limitations (from the reference run)

- Bundled Photos 7.24.0 is from Apr 2025 and will age; Google may eventually require newer
  versions for some features. Never update it from Play Store (module detaches it anyway).
- The module ZIP contains a precompiled binary (`system/bin/gphotos-detach`, ~1.1 MB). It is a
  compiled blob — audit risk accepted knowingly. It only interacts with the Play Store package
  manager to detach Photos from auto-updates.
- `adb root` (userdebug emulator) and Magisk's `su` are **two different roots**. ADB root is not
  Magisk. Verify both.
- If `su -c` returns `Permission denied` or magisk CLI says `Cannot connect to daemon:
  Connection refused`, see §10 Troubleshooting.

---

## 1. Repository layout

```
gphotos-unlimited-emulator-setup/   ← repo root
├── README.md                        ← this file (full reference, all OSes)
├── DEVELOPER.md                     ← human quick guide + background
├── AI_AGENT.md                      ← agent playbook — SELF-CONTAINED:
│                                       works from the text alone; downloads +
│                                       hash-verifies all assets itself (Stage 0)
├── rootavd-windows-patched/         ← ready-to-use Windows rooting kit (optional;
│   ├── rootAVD.bat                  ←   AI_AGENT.md Stage 0 recreates everything
│   ├── rootAVD.sh                   ←   from pinned upstream sources)
│   └── Magisk.zip                   ← Magisk v30.6 APK renamed to ZIP (verified 30600)
└── (host sync folder, see §9 — lives outside the repo)
```

`rootavd-windows-patched/Magisk.zip` is Magisk v30.6 (`MAGISK_VER_CODE=30600`), SHA256
`F1FFC3C9A5614C251BA6BADA308163ACC3C3D844CF01D33F55A8BC151ADC34CE`. The patched
`rootAVD.sh` contains two fixes over upstream (ps16k 16 KB page alignment + non-interactive
early-out); both are documented verbatim in `AI_AGENT.md` Stage 0.5 so any machine can
reproduce them from source.

### 1.1 Publishing to GitHub

From the repo root:

```bash
git init
git add README.md DEVELOPER.md AI_AGENT.md rootavd-windows-patched/ .gitignore
git commit -m "Add GPhotos-Unlimited emulator setup guide and rooting kit"
git branch -M main
git remote add origin https://github.com/<you>/gphotos-unlimited-emulator-setup.git
git push -u origin main
```

The host sync folder (`Documents/Gphotos`) lives outside the repo and is never committed.

---

## 2. Prerequisites (all OSes)

| Requirement | Notes |
|---|---|
| Android Studio + SDK | `emulator`, `platform-tools` (adb) installed |
| `ANDROID_HOME` | Windows: `%LOCALAPPDATA%\Android\Sdk`. macOS: `~/Library/Android/sdk`. Linux: `~/Android/Sdk` |
| ~10 GB free disk | System image (~5 GB) + AVD data |
| adb in PATH | `adb version` must work |
| Emulator running | rootAVD requires the target AVD to be **online** |

Create the AVD (choose **Google APIs** image; Play Store images are `user` type and behave
differently — the reference run used Google APIs / `userdebug`):

```bash
# via Android Studio Device Manager, or:
avdmanager create avd -n <AVD_NAME> -d pixel_10_pro_xl \
  -k "system-images;android-36.1;google_apis;x86_64"
```

If you instead pick a `ps16k` (16 KB page size) image — like the reference machine did — make
sure you use the **patched** `rootAVD.sh` (§4.3), otherwise the fake boot header uses the wrong
page alignment.

Sanity check before continuing:

```bash
adb devices                       # emulator-5554 device
adb -s emulator-5554 shell getprop ro.product.cpu.abi        # x86_64
adb -s emulator-5554 shell getprop ro.build.version.sdk      # 36
adb -s emulator-5554 shell getprop ro.build.type             # userdebug (Google APIs)
adb -s emulator-5554 shell getprop ro.build.fingerprint      # check for 16k/page-size suffix
```

Record the pre-state (for recovery):

```bash
# hash of the stock ramdisk (record this!)
sha256sum "$ANDROID_HOME/system-images/android-36.1/google_apis_ps16k/x86_64/ramdisk.img"
# Windows PowerShell:
# (Get-FileHash ...\ramdisk.img -Algorithm SHA256).Hash
```

Reference hashes from the verified run:

- stock `ramdisk.img` SHA256: `40878E4010B45AB23C394534AE6DF97777F29B1568CADA89D8B946CC54E02D21`
- module ZIP `GPhotos-Unlimited-M-x86_64-MehediHJoy.zip` (85,616,210 bytes),
  contains Google Photos base.apk `versionCode=49953386`, `versionName=7.24.0.747539053`

---

## 3. Research / verify before touching anything

1. Check the module repo releases: <https://github.com/mehedihjoy0/GPhotos-Unlimited/releases>
   - The README says "v5.0"; the actual **latest release tag is `v5.0.0`** (published
     2025-04-21). Same thing, different label.
   - Assets: one ZIP per ABI (`arm64-v8a`, `armeabi-v7a`, `x86`, `x86_64`). Pick **your** ABI.
   - Expanded-asset URL (asset names are hidden behind JS on the releases page):
     `https://github.com/mehedihjoy0/GPhotos-Unlimited/releases/expanded_assets/v5.0.0`
2. Confirm the ZIP architecture: `install.sh` aborts on non-matching ABI, and
   `apks/split_config.<abi>.apk` must exist. Verify by listing the archive.
3. Audit the scripts (`install.sh`, `common/service.sh`, `common/post-fs-data.sh`):
   - they must not download anything from the network during install,
   - they WILL: uninstall stock Photos, `pm clear` Photos app data, detach from Play Store.
   - These are expected destructive ops → **get user approval before installing** if there is
     real Photos data / a signed-in account on the target device.
4. Confirm bundled Photos compatibility: `aapt dump badging apks/base.apk` →
   `versionCode='49953386'`, `compileSdkVersion='36'`, `targetSdkVersion='35'`, `minSdk 23`.
   The module's `module.prop` `versionCode` must equal the bundled APK's versionCode
   (it does — `49953386` — otherwise `service.sh` reinstalls/clears data every boot).

---

## 4. Root the AVD with Magisk 30.6 (rootAVD)

### 4.1 Requirements

- Target AVD **online** (booted).
- Rooting kit in a dedicated folder containing `rootAVD.bat`, `rootAVD.sh`, `Magisk.zip`
  (v30.x for API 35+). API ≤ 34 → v26.4; API 35/36 → v30.x. (Android 17/API 37 → v31.x.)

### 4.2 Run it

**Windows (must be `cmd.exe`, not PowerShell):**

```cmd
cd gphotos-unlimited-emulator-setup\rootavd-windows-patched
rootAVD.bat system-images\android-36.1\google_apis_ps16k\x86_64\ramdisk.img FAKEBOOTIMG
```

(The path after `rootAVD.bat` is **relative to `%LOCALAPPDATA%\Android\Sdk`** — use your own
image directory. `ListAllAVDs` prints the exact line for every installed image.)

**macOS / Linux (Git Bash on Windows also works for the .sh host wrapper):**

```bash
cd rootAVD
./rootAVD.sh system-images/android-36.1/google_apis_ps16k/x86_64/ramdisk.img FAKEBOOTIMG
```

What a successful run looks like (key lines):

```
[*] Testing Busybox /data/data/com.android.shell/Magisk/lib/x86_64/libbusybox.so
[?] Choose a Magisk Version to install and make it local
[1] local stable '30.6' (ENTER)          ← non-tty runs pick this automatically
[+] CLI patch succeeded: /sdcard/Download/magisk_patched-CLI.img
[-] Magisk patched boot image detected
[!] Ramdisk is probably from this AVD    ← kernel release must match
[-] Pull ramdiskpatched4AVD.img into ramdisk.img
[-] Trying to shut down the AVD
```

The AVD shuts down at the end. **Cold-boot it** (no snapshot) afterwards:

```bash
# Windows PowerShell:
& "$env:LOCALAPPDATA\Android\Sdk\emulator\emulator.exe" -avd <AVD_NAME> -no-snapshot-load &
# macOS/Linux:
$ANDROID_HOME/emulator/emulator -avd <AVD_NAME> -no-snapshot-load &
```

### 4.3 The ps16k patch (already applied to the bundled `rootAVD.sh`)

16 KB-page-size images need a 16 KB-aligned fake boot header. In `create_fake_boot_img()`
replace the fixed `PAGESIZE=2048` with:

```sh
# ps16k AVD images need 16K alignment for the fake boot header (qig123/rootAVD2026)
PAGESIZE=2048
if [ -n "$AVDPATHWITHRDFFILE" ] && echo "$AVDPATHWITHRDFFILE" | grep -qi "ps16k"; then
    PAGESIZE=16384
fi
```

### 4.4 Known rootAVD bugs + workarounds (hit in the reference run)

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

### 4.5 Verify Magisk (do NOT proceed before this passes)

```bash
adb devices                                              # online
adb -s emulator-5554 shell pm list packages magisk       # package:com.topjohnwu.magisk
adb -s emulator-5554 root                                # "restarting adbd as root"
adb -s emulator-5554 shell "su -c id"
# expect: uid=0(root) ... context=u:r:magisk:s0
adb -s emulator-5554 shell "su -c 'magisk -v'"           # 30.6:MAGISKSU
adb -s emulator-5554 shell "ps -A" | grep magisk         # magiskd running
```

Also open the Magisk app once on the emulator — the Home card must show
`Installed 30.6 (30600)`, `Ramdisk: Yes`. Do **not** tap "Update" (31.x unverified for this
flow).

If `su -c` says `Permission denied`: MagiskSU policy rejects uid 2000. Grant it via the
Magisk app (Superuser tab) or write the policy DB:

```bash
adb -s emulator-5554 root
adb -s emulator-5554 shell "magisk --sqlite 'INSERT OR REPLACE INTO policies (uid, policy, until) VALUES(2000, 2, 0)'"
```

(`--sqlite` must reach magiskd; run it under `adb root`. If magisk CLI reports
`Cannot connect to daemon`, `magiskd` is dead — reboot the AVD and retry.)

---

## 5. Download + verify the module

```bash
# from the module folder on the host:
curl -L -o GPhotos-Unlimited-M-x86_64-MehediHJoy.zip \
  https://github.com/mehedihjoy0/GPhotos-Unlimited/releases/download/v5.0.0/GPhotos-Unlimited-M-x86_64-MehediHJoy.zip
```

Verify:

- archive contains: `META-INF/com/google/android/update-binary`, `module.prop`, `install.sh`,
  `common/{Photos.apk,detach.txt,post-fs-data.sh,service.sh}`, `apks/base.apk`,
  `apks/split_config.x86_64.apk`, `apks/split_config.xxhdpi.apk`, `system/bin/gphotos-detach`
- `module.prop`: `id=gphotos-unlimited`, `versionCode=49953386`, `updateJson` →
  `raw.githubusercontent.com/mehedihjoy0/GPhotos-Unlimited/x86_64/update.json`
- no checksums are published upstream — verify by (a) downloading only from the official
  release URL and (b) comparing the bundled `base.apk` `versionCode/versionName` via aapt.

**STOP POINT (approval gate):** the installer will replace the system Photos APK and run
`pm clear` on `com.google.android.apps.photos`. If the device has a signed-in account or local
app data, tell the user exactly what will be lost (app-level sign-out only; `/sdcard` media
untouched) and get explicit approval.

---

## 5b. ALTERNATIVE module: Rev4N1/GPhotosUnlimited (Zygisk-based)

A second, more popular implementation exists:
<https://github.com/Rev4N1/GPhotosUnlimited> (GPL-3.0, adapted from osm0sis's Play
Integrity Fork). It works completely differently:

| | §5 mehedihjoy0/GPhotos-Unlimited | §5b Rev4N1/GPhotosUnlimited |
|---|---|---|
| Mechanism | Replaces the Photos APK with a bundled old build (7.24) + bind-mount + Play-detach | Zygisk module spoofs `android.os.Build` fields, system properties, and `PackageManager.hasSystemFeature()` **inside the Photos process only** |
| Photos version | Locked to bundled 7.24 (Apr 2025), never update | Your own Photos, stays updatable |
| Zygisk | Not needed | **Required** (Magisk ≥ 27 with Zygisk enabled) |
| ABI support | x86_64 fine (v5.0.0) | **v5 DROPPED x86/x86_64** (ShadowHook switch) — use **v4** on x86_64 emulators |
| Install size | ~85 MB (contains Photos APK) | ~263 KB |

### Choose ONE module. Never both.

Both target the Photos process; they conflict. To switch from mehedihjoy0 to Rev4N1:

```bash
adb -s emulator-5554 root
adb -s emulator-5554 shell "rm -rf /data/adb/modules/gphotos-unlimited"
adb -s emulator-5554 reboot
```

After reboot the stock/any Photos APK is active again (the mehedihjoy0 bind-mounts vanish).
The Rev4N1 module does NOT need to reinstall Photos — keep the newest Photos you can get.

### Requirements

- Magisk with **Zygisk enabled** (verify in Magisk app Home card: `Zygisk: Yes`; on the
  reference setup it already is). KernelSU/APatch users need Zygisk Next/ReZygisk/NeoZygisk.
- Working Google Play Services + a signed-in Google account (real Photos from Play or
  bundled elsewhere).

### Download (x86_64 → v4 only!)

```bash
curl -L -o GPhotosUnlimited-v4.zip \
  https://github.com/Rev4N1/GPhotosUnlimited/releases/download/v4/GPhotosUnlimited-v4.zip
```

Upstream publishes a checksum — VERIFY it:

- expected: `sha256 3f8cbc84398f66da7c486df09fe955a4937b87dc3e372e38e0824e46e850e7b4`
- size: 263 KB, released 2026-08-11

(v5, tag `v5`, 2026-09-17, is the latest release but explicitly lost x86/x86_64 support —
do not use it on this emulator. Re-check future releases for restored x86_64 support.)

### Install

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

### Verify (different method than §8!)

Rev4N1's README warns the storage tier is **no longer reliably shown** in
Settings → Backup — do not rely on that screen. The real check:

1. Back up a **new** photo (e.g. the synthetic test image from §8.3).
2. Open that photo in Photos, swipe up / tap the ⓘ (details).
3. **Working:** details say the photo does **not** count against your Google Account
   storage.
4. If it says it counts: clear Photos app data + reboot, back up a new photo, re-check.

Storage-before/after accounting (§8.3) is still the honest cross-check.

### Configure / troubleshoot

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

---

## 6. Install the module

### 6.1 CLI (recommended, no UI)

```bash
adb -s emulator-5554 push GPhotos-Unlimited-M-x86_64-MehediHJoy.zip /data/local/tmp/gphotos-module.zip
adb -s emulator-5554 root
adb -s emulator-5554 shell "magisk --install-module /data/local/tmp/gphotos-module.zip"
adb -s emulator-5554 reboot
```

Expected output: architecture check (`x86_64`), "Extracting Module Files", "Setting
permissions", "Done".

Note: `su -c 'magisk --install-module ...'` fails on MagiskSU (it eats `--install-module` as a
su flag). Use **`adb root` + plain `magisk`** for CLI module installs.

Quirk: after CLI install, stray `module.prop` + `update` files may appear directly under
`/data/adb/modules/` (wrong level). Harmless — remove them:

```bash
adb -s emulator-5554 root
adb -s emulator-5554 shell "rm -f /data/adb/modules/module.prop /data/adb/modules/update"
```

### 6.2 GUI (alternative)

Magisk app → Modules → Install from storage → select the ZIP → reboot.

---

## 7. Post-reboot verification

> This section verifies the mehedihjoy0 module (§5). If you installed the Rev4N1 module
> (§5b) instead, verify with `ls /data/adb/modules/unlimitedphotos/`, the Magisk app
> Modules tab, `logcat | grep 'FGP/'` after boot, and the photo-details ⓘ test in §5b —
> there are no Photos bind-mounts and no APK replacement to check.

```bash
# 1. module dir exists and is enabled (no "disable"/"remove" marker files)
adb -s emulator-5554 root
adb -s emulator-5554 shell "ls /data/adb/modules/gphotos-unlimited/"

# 2. Magisk bind-mounts are live
adb -s emulator-5554 shell "grep -i photos /proc/mounts"
# expect: magisk /product/app/Photos tmpfs ro
#         .../system/bin/gphotos-detach ...
#         .../data/app/...com.google.android.apps.photos.../base.apk ...

# 3. Photos is the module's version, installed from /data/app
adb -s emulator-5554 shell "dumpsys package com.google.android.apps.photos | grep -E 'versionName|versionCode='"
# expect: versionCode=49953386  versionName=7.24.0.747539053

# 4. Magisk daemon alive
adb -s emulator-5554 shell "ps -A" | grep magisk

# 5. module service script ran without errors
adb -s emulator-5554 shell "logcat -d -s Magisk:* | tail -20"
# expect: "gphotos-unlimited: exec [service.sh]" and no crash afterwards
```

Launch Photos once (it must not crash), grant the media permission dialog
("Allow all"):

```bash
adb -s emulator-5554 shell monkey -p com.google.android.apps.photos -c android.intent.category.LAUNCHER 1
```

**If magiskd ever dies mid-session** (su says `Cannot connect to daemon`), just reboot the AVD
— the daemon restarts from the patched ramdisk. All module mounts persist either way.

---

## 8. Google Photos configuration + the real test

### 8.1 Sign-in (human-only step)

The emulator ships with **no Google account**. The user must sign in themselves (Settings →
Accounts → Add account → Google, or the Photos prompt). Never handle credentials via
automation. 2FA needs the user.

### 8.2 Check backup quality options (UI eligibility)

> Using the Rev4N1 module (§5b) instead? Skip this screen — Google Photos no longer
> reliably shows the storage tier under Settings → Backup; verify per §5b "Verify"
> (photo details ⓘ) plus the §8.3 storage test.

With the account signed in:

- Photos → Settings → Backup → verify **Backup is ON** for the account.
- Photos → Settings → Backup → **Backup quality**: the unlocked options should include
  **Original quality** (and Storage saver). Note exactly what is selectable — this is
  *eligibility*, not proof.
- Photos → account avatar → check remaining-storage display.

Screenshot the settings screens as evidence.

### 8.3 Upload test (real proof)

Never upload private photos. Use a small synthetic image:

```powershell
# Windows PowerShell — generate 800x600 test JPG
Add-Type -AssemblyName System.Drawing
$bmp = New-Object System.Drawing.Bitmap(800,600)
$g   = [System.Drawing.Graphics]::FromImage($bmp)
$g.Clear([System.Drawing.Color]::FromArgb(52,152,219))
$g.DrawString("GPhotos-Test $(Get-Date -f 'yyyy-MM-dd HH:mm')",
              (New-Object System.Drawing.Font('Arial',48)),
              [System.Drawing.Brushes]::White, 80, 260)
$bmp.Save("$PWD\gphotos-test.jpg",[System.Drawing.Imaging.ImageFormat]::Jpeg)
```

```bash
# before: record account storage from Photos UI or one.google.com/storage
adb -s emulator-5554 shell mkdir -p /sdcard/DCIM/Camera
adb -s emulator-5554 push gphotos-test.jpg /sdcard/DCIM/Camera/
# force a media rescan + open Photos, wait for the upload to finish, then:
adb -s emulator-5554 shell "logcat -d | grep -iE 'upload|backup' | grep -i photos | tail -30"
# after: re-check account storage on one.google.com/storage
```

**Interpretation:**

| Observation | Meaning |
|---|---|
| Storage used does NOT grow after the upload | Unlimited claim **confirmed for this account** (original-quality upload consumed no quota) |
| "Original quality" selectable but storage grows | Module installed fine, but Google still counts it — UI eligibility ≠ unlimited |
| Photos counts the upload under a quota | Same as above; module spoof insufficient |

Record bytes-before / bytes-after / delta in the run log.

### 8.4 What NOT to do

- Do not install/update Google Photos from Play Store (README warning; Play is detached, but
  don't fight it).
- Do not clear Play Store data (`com.android.vending`) — that removes the detach state.
- Do not wipe Photos data after testing (would sign the account out).

---

## 9. Host photo-sync folder (Windows / macOS / Linux)

The host folder feeds the emulator's camera directory. Default pair:

```
host : C:\Users\dipu\Documents\Gphotos        (Windows reference machine)
device: /sdcard/DCIM/Camera
```

Create the folder on the host and sync with one of these (run whenever new photos should land
on the emulator; requires the AVD to be online, serial typically `emulator-5554`):

### Windows (PowerShell, reference implementation)

```powershell
$src = "$env:USERPROFILE\Documents\Gphotos"
adb -s emulator-5554 shell mkdir -p /sdcard/DCIM/Camera
adb -s emulator-5554 push "$src\*" /sdcard/DCIM/Camera/
```

### macOS / Linux

```bash
src="$HOME/Documents/Gphotos"
adb -s emulator-5554 shell mkdir -p /sdcard/DCIM/Camera
adb push "$src"/*.jpg /sdcard/DCIM/Camera/
```

Notes:

- If the emulator serial changes (multiple devices running), list with `adb devices` and
  substitute the right serial everywhere — the scripts above hard-code `emulator-5554` by
  design so they keep working when only one AVD runs.
- After pushing, Photos picks up new media automatically (media scanner); if not, force a
  rescan: `adb shell "am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d file:///sdcard/DCIM/Camera/<file>.jpg"`
- **Never** move/delete the host originals; `adb push` is copy-only.

---

## 10. Troubleshooting (reference-run gotchas)

| Symptom | Cause | Fix |
|---|---|---|
| rootAVD hangs at "Checking available Magisk Versions" | non-TTY menu / version fetch | patched script early-outs to local ZIP (§4.4-1) |
| Magisk app installed but `/data/adb/magisk` empty at first boot | app completes setup on first launch after patched boot | open the app once; verify with `su -c 'magisk -v'` |
| `su -c` → `Permission denied` / log `su: request rejected (2000)` | MagiskSU policy rejects shell | grant via app, or policies DB insert (§4.5) |
| `su: unrecognized option '--install-module'` / `--sqlite` | MagiskSU consumes flags | use `adb root` + plain `magisk ...` |
| `magisk` CLI → `Cannot connect to daemon: Connection refused` | magiskd dead | reboot the AVD |
| `pm list packages magisk` empty after rootAVD | Windows .bat `Apps` bug | §4.4-2 |
| Photos reinstalled + data cleared on every boot | module.prop versionCode ≠ bundled APK versionCode | use intact v5.0.0 ZIP (49953386 = 49953386) |
| uiautomator dump fails with `null root node` | screen off / UI not ready | wake screen (`input keyevent KEYCODE_WAKEUP`), retry |
| Screenshot unreadable / corrupted | PowerShell 5.1 mangles binary redirects | capture with `cmd /c "adb exec-out screencap -p > file.png"` |
| GDI+ "Out of memory" on host PNG | corrupt/incomplete PNG | re-capture via cmd redirect (previous row) |

---

## 11. Restore / recovery

1. **Unroot an AVD's image** (revert Magisk ramdisk):
   ```cmd
   cd gphotos-unlimited-emulator-setup\rootavd-windows-patched
   rootAVD.bat system-images\android-36.1\google_apis_ps16k\x86_64\ramdisk.img restore
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
4. Verify restoration: `sha256sum ramdisk.img` must equal the stock hash recorded in §2.

---

## 12. Agent checklist (for automated execution)

Machine-readable order of operations. **Gates** marked ⛔ require the user and must not be
automated away.

```text
[ ] 1  adb devices                       → emulator online
[ ] 2  getprop abi/sdk/build-type        → x86_64 / 36 / userdebug; record fingerprint
[ ] 3  sha256sum ramdisk.img             → record stock hash
[ ] 4  Module release check              → latest tag, correct-ABI asset, script audit
[ ] 5  rootAVD ... FAKEBOOTIMG           → backup + patch + Magisk.apk + shutdown
[ ] 6  Cold boot (-no-snapshot-load)     → sys.boot_completed=1
[ ] 7  pm list packages magisk           → com.topjohnwu.magisk (install .apk if missing, §4.4-2)
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
