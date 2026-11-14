# Developer Guide — GPhotos-Unlimited Emulator Setup

Human-oriented guide. For the full reference (commands for every OS, recovery, troubleshooting)
see [README.md](README.md). For machine-driven execution see [AI_AGENT.md](AI_AGENT.md).

---

## What you are building

An Android Studio emulator (Android 16 / API 36, x86_64) that runs:

1. **Magisk 30.6** — rooted ramdisk (patched `ramdisk.img`, backups kept)
2. **GPhotos-Unlimited v5.0.0** — Magisk module that swaps in its own Google Photos build,
   detached from the Play Store
3. A host folder (`Documents/Gphotos`) that syncs photos onto the emulator

**Goal:** test whether Google Photos treats the emulator like a Pixel and offers
unlimited original-quality backup. Remember: *UI eligibility is not proof* — the only real
test is an upload that does not consume account storage (README §8.3).

---

## Quick path (Windows)

```
1. Create AVD (Google APIs image, x86_64)
2. Boot it
3. cmd.exe → rootavd-windows-patched\rootAVD.bat <ramdisk path> FAKEBOOTIMG
4. Cold-boot AVD  (emulator -avd <name> -no-snapshot-load)
5. Open Magisk app once  → verify "Installed 30.6", Ramdisk: Yes
6. adb root
7. adb push module.zip → magisk --install-module
8. Reboot → check /proc/mounts + Photos versionCode=49953386
9. Launch Photos → "Allow all" → sign in yourself
10. Backup settings check + small test upload → compare storage before/after
```

Total time: ~30–45 min, most of it waiting for boots.

---

## What you need to know before you start

### The three "roots"

| Mechanism | What it is | When you use it |
|---|---|---|
| `adb root` | AOSP userdebug adbd as uid 0 | module install, Magisk CLI, file inspection |
| `su -c '<cmd>'` | MagiskSU | anything needing Magisk's environment |
| `adb shell` (uid 2000) | plain shell | installs, getprop, UI automation |

They are **not interchangeable**. `su` rejects flags (`su 0 magisk --install-module` fails —
MagiskSU eats the flag). Use `adb root` + plain `magisk` for CLI module work.

### The shared-ramdisk catch

`rootAVD` patches `ramdisk.img` **inside the SDK system image** — shared by all AVDs using
that image. Your other AVDs get Magisk too (probably harmless, but know it). Restore:

```
rootAVD.bat <ramdisk path> restore
```

### Why Magisk 30.6 specifically

- API 35/36 need Magisk ≥ 27 (older versions fail to patch GKI-style boot images).
- 30.6 handles the multi-cpio + `init-ld` layout of the Android 16 emulator ramdisk.
- 31.x exists but was unverified in the reference run — don't upgrade mid-flow.

### Why Photos versionCode 49953386 matters

The module's `module.prop` `versionCode` must equal the bundled Photos APK's `versionCode`.
If they ever diverge, `service.sh` reinstalls the APK and runs `pm clear` **on every boot** —
you lose the account session each reboot. If you rebuild a module, keep them identical.

### Photos must never be updated from Play

The mehedihjoy0 module detaches Photos from the Play Store (detach.txt + gphotos-detach
binary). Also this reference AVD has no Play Store at all (`google_apis` image). Do not
"helpfully" sideload a newer Photos — the spoof targets 7.24.0 behavior.

### Alternative module: Rev4N1/GPhotosUnlimited (Zygisk)

A cleaner, more popular module exists: `github.com/Rev4N1/GPhotosUnlimited` (GPL-3.0,
PIFork-based). It spoofs Build fields/props/`hasSystemFeature` **in-process via Zygisk** —
no APK replacement, no Play detach, your Photos stays current. Full setup: README §5b and
AI_AGENT.md "ALTERNATIVE module" section. Two hard facts:

1. **Latest release v5 dropped x86/x86_64 support** — on this x86_64 emulator pin **v4**
   (upstream publishes its sha256; verify it).
2. Run **one module only** — remove the mehedihjoy0 module before installing it, and verify
   via a newly backed-up photo's details ⓘ ("does not count against storage"), not the
   Backup settings screen.

---

## Updating this setup for future releases

When a new module release appears:

1. Read the release notes + changelog diff.
2. Download the correct-ABI asset from the **official releases page only**.
3. Verify: ZIP contents (`apks/split_config.<abi>.apk` present), `module.prop` versionCode,
   bundled APK versionCode (aapt), scripts contain no network calls.
4. Uninstall old module (`rm -rf /data/adb/modules/gphotos-unlimited` + reboot) before
   installing the new one.
5. Re-run the full test in README §8 — storage delta, not just UI.

When a new Magisk release appears: re-verify the whole rootAVD flow on a scratch AVD first.
Never upgrade Magisk in-place on a working emulator (32 MB ramdisk patch + module layout can
change).

---

## Recovery cheat sheet

| Problem | Fix |
|---|---|
| Want AVD unrooted | `rootAVD.bat <ramdisk> restore` (or copy `*.backup` back) |
| Remove module, keep Magisk | `adb root; rm -rf /data/adb/modules/gphotos-unlimited; reboot` |
| su says `Permission denied` | grant in Magisk app Superuser tab, or policies DB insert (README §4.5) |
| su says `Cannot connect to daemon` | reboot the AVD (magiskd died) |
| Photos reinstalls/clears each boot | module.prop versionCode mismatch — re-verify ZIP |
| Everything broken | wipe AVD data + restore ramdisk backups |

---

## Files in this folder

```
README.md               full reference guide (all OSes, recovery, agent checklist)
DEVELOPER.md            this file — human quick guide + background
AI_AGENT.md             agent execution playbook (stop gates, verification, gotchas)
rootavd-windows-patched/
    rootAVD.bat         launcher (cmd.exe only)
    rootAVD.sh          on-device patcher, ps16k-fixed + non-interactive fix
    Magisk.zip          Magisk v30.6 APK (verify 30600 before reuse)
```

Host sync folder (created if missing): `C:\Users\dipu\Documents\Gphotos` → pushed to
`/sdcard/DCIM/Camera/`. See README §9 for macOS/Linux variants and for updating the serial
if it ever changes.
