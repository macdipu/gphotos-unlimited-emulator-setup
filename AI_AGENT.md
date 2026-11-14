# AI Agent Playbook — gphotos-unlimited-emulator-setup

**Self-contained.** This file works even if you only have this text — every asset is
downloaded from pinned official sources and verified by hash. No companion files required.

You are an agent (AI or scripted bot) executing this setup autonomously.
Complements `README.md` (full reference) and `DEVELOPER.md` (human guide).

---

## Mission

Take an existing Android Studio emulator (Android 16 / API 36, x86_64, `userdebug`) and:
(1) root it with Magisk 30.6 via rootAVD, (2) install the GPhotos-Unlimited v5.0.0 module (or the Rev4N1 alternative, see the ALTERNATIVE section),\n(3) configure Google Photos, (4) measure whether Pixel-style unlimited original-quality
backup is actually granted — with evidence, not assumptions.

---

## Hard rules

1. **Never** handle Google account credentials or 2FA. Sign-in is a human step.
2. **Never** upload the user's real photo collection. Test uploads must be synthetic
   images you generate yourself (Stage 12).
3. **Stop and ask before** any of: wiping emulator data, replacing boot images, clearing an
   app's data with real content behind it, changing account configuration, installing an
   unverified module/asset.
4. **Never** delete or overwrite an existing AVD. The rooting flow auto-creates
   `ramdisk.img.backup` / `kernel-ranchu.backup` in the system-image directory.
5. Download **only** from official/pinned sources (Stage 0). No mirrors.
6. Record everything in the run log (template at bottom).

---

## Stage 0 — Bootstrap (self-contained: download all assets)

Set your SDK path first:

```bash
# Windows (PowerShell):      $SDK = "$env:LOCALAPPDATA\Android\Sdk"
# macOS:                     export SDK=~/Library/Android/sdk
# Linux:                     export SDK=~/Android/Sdk
# Also put $SDK/platform-tools (adb) and $SDK/emulator on PATH.
```

Create a workspace and fetch everything:

```bash
mkdir -p gphotos-work && cd gphotos-work

# 1. rootAVD (pinned commit of maintained fork galihlasahido/rootAVD, 2026-09-27)
git clone --depth 1 https://github.com/galihlasahido/rootAVD
cd rootAVD
git fetch --depth 1 origin 0043bd2d8f8479850ee466fd8751e7273c976a7e
git checkout 0043bd2d8f8479850ee466fd8751e7273c976a7e 2>/dev/null || true

# 2. Magisk v30.6 (bundled asset of that pinned commit — verified for API 35/36)
#    Replace the repo's v26.4 default with it:
cp Magisk30.zip Magisk.zip        # or: curl -LO raw.githubusercontent.com/galihlasahido/rootAVD/0043bd2d8f8479850ee466fd8751e7273c976a7e/Magisk30.zip
#    VERIFY (must match; size 12919431 bytes):
#    SHA256 = F1FFC3C9A5614C251BA6BADA308163ACC3C3D844CF01D33F55A8BC151ADC34CE
#    If hash differs → STOP. Do not proceed with an unverified Magisk build.

# 3. GPhotos-Unlimited v5.0.0 module, x86_64 asset (official release URL)
curl -L -o GPhotos-Unlimited-M-x86_64-MehediHJoy.zip \
  https://github.com/mehedihjoy0/GPhotos-Unlimited/releases/download/v5.0.0/GPhotos-Unlimited-M-x86_64-MehediHJoy.zip
#    Reference size: 85616210 bytes. No upstream checksums exist — verify contents
#    in Stage 2 (archive listing + aapt) instead.
cd ..
```

Hash commands: Windows `Get-FileHash <file> -Algorithm SHA256`; macOS `shasum -a 256`;
Linux `sha256sum`.

### Stage 0.5 — Apply the two rootAVD.sh patches (mandatory)

The pinned script has two defects that break API 36 `ps16k` images and non-interactive runs.
Apply BOTH. `PAGESIZE=2048` appears exactly once in the file — safe for targeted replace.

Patch A — ps16k 16 KB page alignment (inside `create_fake_boot_img()`):

```bash
python3 - <<'EOF'
import re, pathlib
p = pathlib.Path("rootAVD.sh")
s = p.read_text()
old = 'RAMDISK_SZ="$(printf \'%08x\' $(stat -c%s $CPIO))"\n\tPAGESIZE=2048'
new = ('RAMDISK_SZ="$(printf \'%08x\' $(stat -c%s $CPIO))"\n'
       '\t# ps16k AVD images need 16K alignment (qig123/rootAVD2026)\n'
       '\tPAGESIZE=2048\n'
       '\tif [ -n "$AVDPATHWITHRDFFILE" ] && echo "$AVDPATHWITHRDFFILE" | grep -qi "ps16k"; then\n'
       '\t\tPAGESIZE=16384\n'
       '\tfi')
assert s.count("PAGESIZE=2048") == 1, "upstream changed; stop and re-audit"
s = s.replace(old, new, 1)
p.write_text(s)
print("patch A ok")
EOF
```

Patch B — non-interactive early-out (skip version-menu hang when stdin is not a TTY),
inserted at the top of `CheckAvailableMagisks()`:

```bash
python3 - <<'EOF'
import pathlib
p = pathlib.Path("rootAVD.sh")
s = p.read_text()
anchor = "if [ -z $MAGISKVERCHOOSEN ]; then\n"
assert s.count(anchor) >= 1, "anchor missing; stop and re-audit"
inject = anchor + """
\t\t# Non-interactive: skip version fetch/menu, use bundled local Magisk.zip
\t\tif [ ! -t 0 ]; then
\t\t\tUFSH=$BASEDIR/assets/util_functions.sh
\t\t\tMAGISK_LOCL_VER=$($BB grep $UFSH -e "MAGISK_VER" -w | sed 's/^.*=//')
\t\t\tMAGISK_LOCL_VER_CODE=$($BB grep $UFSH -e "MAGISK_VER_CODE" -w | sed 's/^.*=//')
\t\t\tMAGISK_VER=$(GetPrettyVer $MAGISK_LOCL_VER $MAGISK_LOCL_VER_CODE)
\t\t\tMAGISKVERCHOOSEN=false
\t\t\techo "[!] Non-interactive mode: using local Magisk $MAGISK_VER"
\t\t\treturn 0
\t\tfi
"""
s = s.replace(anchor, inject, 1)
p.write_text(s)
print("patch B ok")
EOF
```

If neither patch applies (anchor text changed upstream), STOP and re-audit the script
manually. Do not run an unaudited rooting script.

---

## Stage 1 — Verify environment

```bash
adb devices                     # exactly one emulator, online
adb -s emulator-5554 shell getprop ro.product.cpu.abi      # x86_64
adb -s emulator-5554 shell getprop ro.build.version.sdk    # 36
adb -s emulator-5554 shell getprop ro.build.type           # userdebug
adb -s emulator-5554 shell getprop ro.build.fingerprint    # note ps16k/16k suffix
```

Any mismatch → STOP, report exact values.

## Stage 2 — Verify the module ZIP before touching the device

```bash
# archive must contain: META-INF/com/google/android/update-binary, module.prop,
# install.sh, common/{Photos.apk,detach.txt,post-fs-data.sh,service.sh},
# apks/base.apk, apks/split_config.x86_64.apk, apks/split_config.xxhdpi.apk,
# system/bin/gphotos-detach
# extract apks/base.apk then:
aapt dump badging base.apk
# expect: versionCode='49953386'  versionName='7.24.0.747539053'
#         compileSdkVersion='36'  targetSdkVersion='35'  minSdk 23
```

Also: grep the module's `install.sh` / `service.sh` / `post-fs-data.sh` for `curl|wget|http`
— there must be **no network calls** in install-time scripts. And the module.prop
`versionCode` (49953386) must equal the bundled APK's versionCode — otherwise service.sh
reinstalls + `pm clear`s Photos on every boot (STOP if mismatch).

## Stage 3 — Record pre-state

```bash
sha256sum "$SDK/system-images/android-36.1/google_apis_ps16k/x86_64/ramdisk.img"
# reference stock hash:
# 40878E4010B45AB23C394534AE6DF97777F29B1568CADA89D8B946CC54E02D21
adb -s emulator-5554 shell "dumpsys package com.google.android.apps.photos | grep versionCode"
adb -s emulator-5554 shell "dumpsys account | grep -c 'Account {'"   # existing accounts
adb -s emulator-5554 shell "ls /sdcard/DCIM"                          # real photos?
```

⛔ If a Google account is signed in or real Photos app data exists → ask the user before
proceeding (module clears Photos **app data**; `/sdcard` media is untouched).

## Stage 4 — Root with rootAVD

Emulator must be **online**. The ramdisk path is **relative to $SDK**.

```bash
# Windows — MUST run from cmd.exe, not PowerShell:
#   cd gphotos-work\rootAVD
#   cmd /c "rootAVD.bat system-images\android-36.1\google_apis_ps16k\x86_64\ramdisk.img FAKEBOOTIMG"
# macOS / Linux:
cd rootAVD
./rootAVD.sh system-images/android-36.1/google_apis_ps16k/x86_64/ramdisk.img FAKEBOOTIMG
```

Success markers (must ALL appear):

```
[-] Backup File was created
[?] Choose a Magisk Version ... [1] local stable '30.6' (ENTER)
[+] CLI patch succeeded: /sdcard/Download/magisk_patched-CLI.img
[-] Magisk patched boot image detected
[!] Ramdisk is probably from this AVD          ← kernel release must match
[-] Pull ramdiskpatched4AVD.img into ramdisk.img
[-] Trying to shut down the AVD
```

Known upstream bug (Windows .bat): it pulls `Magisk.apk` into a **file** named `Apps`
instead of an `Apps/` folder, so auto-install installs nothing. Fix:

```bash
cd rootAVD
rm -f Apps && mv Magisk.apk . && mkdir -p Apps && mv Magisk.apk Apps/Magisk.apk
# cold-boot first (Stage 5), then:
adb install -r Apps/Magisk.apk
```

## Stage 5 — Cold boot

```bash
"$SDK/emulator/emulator" -avd <AVD_NAME> -no-snapshot-load &   # background it
# poll until: adb shell getprop sys.boot_completed == 1  (timeout 4 min, poll 5 s)
```

## Stage 6 — Verify Magisk (hard gate)

```bash
adb devices                                            # online
adb -s emulator-5554 shell pm list packages magisk     # com.topjohnwu.magisk
adb -s emulator-5554 root                              # "restarting adbd as root"
adb -s emulator-5554 shell "su -c id"                  # uid=0 ... context=u:r:magisk:s0
adb -s emulator-5554 shell "su -c 'magisk -v'"         # 30.6:MAGISKSU
adb -s emulator-5554 shell "ps -A" | grep magisk       # magiskd running
```

Also open the Magisk app once: Home card must show `Installed 30.6 (30600)`,
`Ramdisk: Yes`. Do **not** tap "Update" (31.x unverified).

- `su -c` → `Permission denied`: grant policy under `adb root`:
  `magisk --sqlite 'INSERT OR REPLACE INTO policies (uid, policy, until) VALUES(2000, 2, 0)'`
- magisk CLI → `Cannot connect to daemon`: magiskd died → reboot AVD, retry.

## Stage 7 — Install module (CLI)

Do NOT use `su -c 'magisk --install-module'` — MagiskSU eats the flag. Use `adb root`:

```bash
adb -s emulator-5554 root
adb -s emulator-5554 push GPhotos-Unlimited-M-x86_64-MehediHJoy.zip /data/local/tmp/gphotos-module.zip
adb -s emulator-5554 shell "magisk --install-module /data/local/tmp/gphotos-module.zip"   # → "Done"
adb -s emulator-5554 reboot
# poll boot_completed
# cleanup stray files from the CLI installer:
adb -s emulator-5554 root
adb -s emulator-5554 shell "rm -f /data/adb/modules/module.prop /data/adb/modules/update"
```

## Stage 8 — Verify module

```bash
adb -s emulator-5554 root
adb -s emulator-5554 shell "ls /data/adb/modules/gphotos-unlimited/"   # no disable/remove markers
adb -s emulator-5554 shell "grep -i photos /proc/mounts"
#   magisk /product/app/Photos tmpfs ro
#   .../system/bin/gphotos-detach ...
#   .../data/app/...com.google.android.apps.photos.../base.apk ...
adb -s emulator-5554 shell "dumpsys package com.google.android.apps.photos | grep -E 'versionName|versionCode='"
#   versionCode=49953386  versionName=7.24.0.747539053
adb -s emulator-5554 shell "logcat -d -s Magisk:* | tail -20"
#   "gphotos-unlimited: exec [service.sh]", no crash
```

## Stage 9 — Launch Photos

```bash
adb -s emulator-5554 shell monkey -p com.google.android.apps.photos -c android.intent.category.LAUNCHER 1
# permission dialog → tap "Allow all" (coords from screencap, see gotchas)
adb -s emulator-5554 shell "dumpsys activity top | grep ACTIVITY | head -2"   # Photos in foreground
adb -s emulator-5554 shell "logcat -d | grep -E 'FATAL|AndroidRuntime'"        # must be empty
```

## ⛔ Stage 10 — Human step: Google sign-in

Never automate credentials. Offer: the sign-in screen Photos shows, or
Settings → Passwords & accounts → Add account → Google. Wait for user confirmation, then
verify: `adb shell "dumpsys account | grep -c 'Account {'"` ≥ 1.

## Stage 11 — Backup eligibility (UI evidence, not proof)

Navigate Photos → Settings → Backup via adb taps + screenshots (downscale screenshots to
≤600 px for inline reading). Record: Backup ON? Which quality options are selectable
(Original / Storage saver / ...)? Screenshot each screen into the run-log folder.

## ⛔ Stage 12 — Upload test (only with user approval)

```bash
# BEFORE: record account storage bytes (user reads one.google.com/storage or the
# Photos storage card — screenshot it).
# generate synthetic 800x600 JPG (System.Drawing on Windows / PIL elsewhere):
adb -s emulator-5554 shell mkdir -p /sdcard/DCIM/Camera
adb -s emulator-5554 push gphotos-test.jpg /sdcard/DCIM/Camera/
# wait for backup to complete (Photos UI / logcat upload lines), then:
# AFTER: re-read storage bytes. Record before / after / delta.
```

Interpretation:

| Storage delta | Meaning |
|---|---|
| 0 bytes | unlimited original-quality claim **confirmed** for this account |
| > 0 bytes | module installed, but UI eligibility ≠ unlimited — report honestly |

## Stage 13 — Final report

AVD config / Magisk version / module version + source URL / Photos version /
install status / eligibility / measured result / limitations / recovery steps.
Attach screenshots, hashes, log excerpts, storage deltas.

## Stage 14 — Sync script preservation

The user's host sync script targets serial `emulator-5554` and folder
`~/Documents/Gphotos → /sdcard/DCIM/Camera`. If the serial changed (multiple AVDs running),
tell the user exactly which string to edit — never rewrite their script unasked.

---

## ALTERNATIVE module: Rev4N1/GPhotosUnlimited (Zygisk-based)

If the user asks for `github.com/Rev4N1/GPhotosUnlimited` instead of the mehedihjoy0 module
used above, switch paths — the Magisk rooting stages (0–8) are identical.

**Critical ABI rule:** latest Rev4N1 release **v5 dropped x86/x86_64 support** (ShadowHook
switch). On an x86_64 emulator you MUST pin **v4**. Re-check each new release for restored
x86_64 support before ever moving past v4.

**Bootstrap (replaces the mehedihjoy0 module download in Stage 0):**

```bash
curl -L -o GPhotosUnlimited-v4.zip \
  https://github.com/Rev4N1/GPhotosUnlimited/releases/download/v4/GPhotosUnlimited-v4.zip
# upstream-published checksum — verify before install:
# sha256 3f8cbc84398f66da7c486df09fe955a4937b87dc3e372e38e0824e46e850e7b4  (263 KB, 2026-08-11)
```

**Rules:**

- **ONE module only.** If `gphotos-unlimited` (mehedihjoy0) is installed, remove it first:
  `adb root; rm -rf /data/adb/modules/gphotos-unlimited; adb reboot` — then install Rev4N1.
- Zygisk must be enabled (Magisk app Home card shows `Zygisk: Yes`; it is on the reference
  setup). Rev4N1 keeps the user's own Photos APK — no version replacement, no detach hacks.
- Module id/dir: `/data/adb/modules/unlimitedphotos/`.

**Install:**

```bash
adb -s emulator-5554 root
adb -s emulator-5554 push GPhotosUnlimited-v4.zip /data/local/tmp/gphotos-zygisk.zip
adb -s emulator-5554 shell "magisk --install-module /data/local/tmp/gphotos-zygisk.zip"
adb -s emulator-5554 reboot
```

First install auto-runs `autofgp.sh` (generates a random fingerprint from a random official
Pixel/Pixel XL 2016 build; needs internet, else bundled default fingerprint).

**Verify — different from the mehedihjoy0 flow:**

```bash
adb -s emulator-5554 shell "ls /data/adb/modules/unlimitedphotos/"
adb -s emulator-5554 shell "logcat | grep 'FGP/'"      # module logs right after boot
# Photos must NOT be on Magisk DenyList (Enforce DenyList interferes)
```

Do NOT trust Settings → Backup for the tier (unreliable in recent Photos versions). The
valid check: back up a **new** synthetic photo → open it → swipe up / tap ⓘ → details must
say it does **not** count against account storage. If it counts: clear Photos app data +
reboot + new photo + re-check. Still record storage before/after for the honest delta.

**Config (root shell, module dir):** `sh autofgp.sh` regenerate fingerprint;
`custom.fgp.json` advanced toggles (`spoofBuild`=1, `spoofProps`=0, `spoofProvider`=0,
`spoofSignature`=0, `spoofFeatures`=1, `verboseLogs`=0..100); `custom.app_replace_list.txt`
for conflicting ROM spoof apps.

---

## Run log template

```text
date / host-os / SDK path / avd-name / image-path / abi / sdk
stock ramdisk sha256:
rootAVD commit: 0043bd2d8f8479850ee466fd8751e7273c976a7e
magisk zip sha256: F1FFC3C9A5614C251BA6BADA308163ACC3C3D844CF01D33F55A8BC151ADC34CE
module asset + size + source URL:
photos versionCode before / after:
backup quality options shown:
storage before / after / delta:
outcome: <confirmed-unlimited | eligibility-only | failed>
```

---

## Gotchas table

| Symptom | Fix |
|---|---|
| rootAVD hangs at "Checking available Magisk Versions" | patched script early-outs to local ZIP (Patch B) |
| Windows .bat `Apps` file instead of folder | Stage 4 workaround |
| `su -c` → `Permission denied` / `request rejected (2000)` | policies DB insert (Stage 6) |
| `su: unrecognized option '--install-module'` | use `adb root` + plain `magisk` (Stage 7) |
| magisk CLI `Cannot connect to daemon` | magiskd dead → reboot AVD |
| Photos reinstalled + `pm clear` each boot | module.prop vs APK versionCode mismatch → Stage 2 |
| `uiautomator dump` → `null root node` | wake screen (`input keyevent KEYCODE_WAKEUP`), retry 5 s |
| Screenshot corrupted via PowerShell redirect | capture via `cmd /c "adb exec-out screencap -p > f.png"` |
| GDI+ "Out of memory" reading PNG | corrupt PNG from previous row; re-capture |
| GitHub API 403 rate limit | scrape HTML pages (expanded_assets), don't retry-spam |
| Long shell command timeout | retry larger timeout; re-verify state, don't assume |

## State re-verification after any interruption

Never assume a stage completed after a timeout/restart. Re-check in order:

```bash
adb devices
getprop sys.boot_completed
ls /data/adb/modules/gphotos-unlimited/
grep -i photos /proc/mounts
dumpsys package com.google.android.apps.photos | grep versionCode
ps -A | grep magisk
```

Resume from the first failing step.

## Reporting integrity rules

- Distinguish explicitly: **module installed** ≠ **eligibility shown** ≠ **storage effect
  measured**. Report all three separately with evidence.
- If a check cannot be completed, say so and why. No inference-filled gaps.
- Positive storage delta → module does NOT provide unlimited backup for this account,
  regardless of UI.
