# Journal: a black-and-white camera for the original iPhone

This is a running log of building **Silver**, a live black-and-white camera app for the 2007 iPhone (iPhone1,1) on iPhone OS 3.1.3. It's written as raw material for a blog post. Entries are in order and include dead ends, with the numbers as measured. The detailed reference material is in [build-vm.md](build-vm.md) and [private-camera-re.md](private-camera-re.md).

## The goal

- A camera app for a jailbroken original iPhone running 3.1.3, the last firmware it supports.
- A live black-and-white viewfinder that isn't a slideshow.
- Film grain on the finished photo.
- A way to get photos off the phone without a cable.
- The look takes after a friend's modern camera app: black chrome, a gold moon shutter button and film "cards".

## Hardware and software constraints

- **CPU and GPU.** The CPU is a 412 MHz ARM11 (ARMv6, with no NEON). The GPU is a PowerVR MBX Lite. The firmware only ships `OpenGLES.framework/MBXGLEngine.bundle`, which means OpenGL ES 1.1 and no shaders.
- **Camera.** It has 2 megapixels and fixed focus, with no flash, no video and no front camera.
- **No usable live-camera API.** iPhone OS 3.1 only lets apps draw on top of `UIImagePickerController`'s preview. Live frames (`AVCaptureVideoDataOutput`) arrived with iOS 4, which this phone never got.

## Day 1: a build machine from 2011

### The VM

Xcode 3.2.6 with the iOS 4.3 SDK is the last toolchain that targets armv6 and iPhone OS 3. It needs Mac OS X 10.6 Snow Leopard. That runs here in **Virtual Intel Mac**: QEMU `qemu-system-x86_64` with TCG, emulating a Penryn CPU on an Apple Silicon Mac. QEMU's user-mode network forwards host port 2223 to the VM's SSH and port 1446 to its SMB. From inside the VM, `10.0.2.2` reaches the host's loopback interface.

### SSH

The VM runs OpenSSH 5.2, which knows only `ssh-rsa` and `ssh-dss`. Today's OpenSSH refuses both by default, so connecting needs `HostKeyAlgorithms=+ssh-rsa` and `PubkeyAcceptedAlgorithms=+ssh-rsa`, plus a dedicated RSA key (5.2 predates ed25519).

To get the key into the VM, the host served it over HTTP on loopback and the VM fetched it from `10.0.2.2`. The key was still refused. `/var/log/secure.log` explained: `Authentication refused: bad ownership or modes for directory /Users/alice`. Turning on File Sharing had made the home folder world-writable (`drwxrwxrwx+`); `chmod 755 ~` fixed it.

### Mounting the VM in Finder

- **Guest → host doesn't work.** Snow Leopard's SMB client only speaks SMB1. The current macOS SMB server closes the connection on an SMB1 `NEGOTIATE`, which a 10-line Python probe confirmed.
- **Host → guest does.** The Mac connects to `127.0.0.1:1446`, and macOS's SMB client still allows SMB1.
- **A password that wasn't the problem.** Logins failed even with the right password. With smbd debug logging on, Samba 3.0.28 reported `spnego_parse_auth failed at 396`: it can't parse the login token that today's macOS SMB client sends. Adding `use spnego = no` to the site section of `/etc/smb.conf` fixed it.
- **A wrong URL.** Finder had also been sent to `smb://alice@127.0.0.1/alice`, without the port, so it was logging in to the Mac itself. The macOS unified log showed this (`NetAuthSysAgent ... URL = ...`).

### Installing Xcode 3.2.6

- **Expired certificate.** The installer stopped with "An unknown installation error occurred". `/var/log/install.log` gave the real cause: `iPhoneSDKTools.pkg is untrusted ... CSSMERR_TP_CERT_EXPIRED`. Apple's package-signing certificate has expired, so the fix is to set the VM's clock to June 2011 for the install.
- **Phantom iTunes.** The MobileDevice package then demanded we quit iTunes, which wasn't open. The background `iTunesHelper` counts as iTunes; killing it let the install continue.
- **Network time.** Turning network time back on failed because the VM had no `/etc/ntp.conf`.

## Day 1: reverse engineering the camera

### Getting the firmware binaries

- **Download.** The 3.1.3 iPhone1,1 restore image (`7E18`) is still on Apple's CDN.
- **Decryption.** The root filesystem DMG is FileVault-encrypted. Its published key comes from the ipsw.me API, since theapplewiki.com sat behind a Cloudflare challenge. A 25-line Python `vfdecrypt` handles the decryption: AES-128-CBC per 4 KB chunk, with each chunk's IV from HMAC-SHA1 of its index.
- **The shared cache.** System libraries live in `dyld_shared_cache_armv6` (format `dyld_v1   armv6`). Three tools failed on it:
  - `ipsw` couldn't parse it (`EOF`);
  - radare2's extractor produced 0 files;
  - KennyTM's 2010 `dyld_decache`, rebuilt for arm64, wrote corrupted Mach-O headers.

  So we wrote our own: `tools/re/dsc.py` reads the cache in place (mappings, images, load commands, symbol tables, stubs and Objective-C 2 classes), and `tools/re/armdis.py` disassembles with Capstone and resolves stubs, `pc`-relative literals and CFStrings.

### What Apple's Camera app does on 3.1.3

`PLCameraController` → `AVCapture` (Celestial) → `FigRecorder` (which can run out of process) → `H1ISP.mediacapture` → a Core Animation image queue on the preview layer. There's no obvious place to read pixels.

### The find: Camera.framework

It's a tiny private C API, about 6 KB of code, left over from iPhone OS 2. Nothing in 3.1.3 calls it anymore. Its disassembly shows:

- `CameraDeviceCreate` opens the `IOCameraSensor` IOKit service directly in the calling process.
- `CameraDeviceStartPreview` allocates **six 304×400 BGRA surfaces** and queues hardware captures into them.
- Each finished frame is handed to a client callback as `cb(dev, 8, surface, refcon)` on our run loop.
- The client must give each surface back with `CameraDeviceRecycleSurface`, or the stream stops after six frames.
- `CameraDeviceTakePhoto` captures a 1600×1200 `'yuvs'` still, compresses it with the hardware JPEG encoder (`AppleJPEGDriver`) and calls back with the JPEG data and a 400×300 thumbnail.

### First light

A 100-line probe app confirmed it on the device:

```
CameraDeviceCreate -> 0x00000000
first frame: 304x400 rowBytes 1216 format 42475241
13.3 fps, memcpy 21.02 ms/frame
```

That's live color frames, as raw pixels, in our own process, on a 2007 phone.

## Day 1: making it fast

### The ARMv6 assembly gray converter

`probe/gray.s`, later `app/gray.s`, is the hot loop: BGRA → luma → a 256-entry table lookup. Per pixel it uses two `uxtb16`s, one `smuad` and one `smlad` (Y = (29·B + 150·G + 77·R) >> 8), then a `uxtb …, ror #8` and one `ldr` from the table. It handles four pixels per `ldmia`/`stmia`.

The table is also the "film stock" tone curve, so the live preview gets curves for free. It matches the C reference exactly: 0 mismatches over 121,600 pixels.

| On the first frame (304×400) | Time |
| --- | --- |
| `memcpy` from camera memory | 8 ms |
| assembly gray, from camera memory | 11.4 ms |
| assembly gray, `malloc` → `malloc` | 6.3 ms |
| plain C gray, `malloc` → `malloc` | 14.3 ms |

### Displaying without copies

A `CoreSurfaceBuffer` can be used directly as `CALayer.contents`. The pipeline writes the gray frame into one of two display surfaces and swaps `layer.contents` between them. The whole live loop takes about 10 ms per frame, against 25 ms for the first probe's color `CGImage` path.

### Dead end: the hardware copy engine

`CoreSurfaceAcceleratorTransferSurface` could only write into `"PurpleGfxMem"` or `"PurpleEDRAM"` memory. It took 8–9 ms, and every sampled pixel came out different from the source. Every other destination format and memory type failed with `0xe00002c7` or `0xe00002c8`.

### The frame-rate ceiling

Frame rates fall into steps: 14.6, 12.5, 6.6 and 5.5 fps. Auto-exposure lengthens frames in dim light, and Apple's driver hard-codes 15 as `ImagerSupportedMaxFrameRateForCurrentResolution`.

The sensor's internal "variables" are reachable through the same `IOCameraSensor` connection (selector 3 reads, selector 4 writes), and they match the Micron **MT9D112**'s map:

| Variable | Address | Meaning |
| --- | --- | --- |
| `seq.cmd` | `0x10003` | write 5 to apply changes |
| `ae.maxIndex` | `0x2000c` | Apple's default is `0x12` |
| preview frame lines | `0x70023` | 675 |
| preview line length | `0x70025` | 1250 |

Shortening the line length to 800–1100 made it *slower* (7–11.5 fps). Restoring the values brought back 14.6 fps. 15 fps is the real ceiling. Silver sets `ae.maxIndex = 4` so the preview stays near 15 fps in dim light, accepting a darker, noisier image, which suits a film look.

## Day 1: the app

### Remote development loop

`scripts/deploy` does the whole cycle:

1. Copies the source into the VM with `tar` over SSH and runs `make` with `gcc-4.2 -arch armv6 -miphoneos-version-min=3.1`.
2. Fake-signs the binary on the Mac with `ldid` from nixpkgs. The phone's own `codesign_allocate` rejects Xcode 3.2.6 output (`unknown load command 4`).
3. Copies it into `/Applications` on the phone and runs `uicache`.
4. Launches it with `uiopen silver:`.

The app registers a `silver://` URL scheme with development commands: `shutter`, `share`, `screenshot` and others. The screenshot command uses `UIGetScreenImage` and writes a PNG to `/tmp`, so the whole loop runs without touching the phone:

- launch;
- press the shutter;
- capture the screen;
- pull the log and PNGs over SSH.

The probe app's scheme only worked after one SpringBoard restart; Silver's worked on first install.

### Crash: bitmap contexts on iPhone OS 3

The first photo crashed in `FilmDevelop` (found by symbolicating the crash report with `atos` in the VM). `CGBitmapContextCreate(NULL, …)` only allocates memory itself from iOS 4 on. On 3.x the caller has to supply the buffer.

### Developing a photo

The steps are:
1. The camera's JPEG is decoded with Core Graphics.
2. It's drawn rotated into a 1200×1600 8-bit gray context.
3. The film stock's tone curve and grain are applied (`app/Film.c`).
4. The result is written as JPEG through ImageIO (looked up with `dlopen`: ImageIO is a private framework on 3.1.3).

The grain is a 256×256 tile of blurred, roughly Gaussian noise, sampled at two scales with random offsets. Its strength depends on brightness, peaking in the midtones.

The first measured develop took 6.4 s: 3.5 s to decode and rotate, 0.4 s for grain and 1.5 s to encode.

### Matching the photo to the viewfinder

The first photos seemed darker than the viewfinder. Measured against a screenshot taken a moment later, the gap was small: the 10th, 50th and 90th brightness percentiles were 33, 100 and 136 on screen and 30, 96 and 137 in the photo. That's 3–4 levels darker in the shadows and midtones.

The likely cause was the gray conversion. The viewfinder uses our own luma weights (29·B + 150·G + 77·R) >> 8, while the photo let Core Graphics convert RGB → DeviceGray, which uses its own color conversion. The develop step now:
- decodes into BGRA;
- converts with the same weights as `gray.s`, rotating in 16×16 tiles in the same pass;
- scales brightness so the photo's mean matches the viewfinder's mean when the shutter was pressed (gain clamped to 0.5–3×).

On the next photo the camera's own exposure already matched: preview mean 117.0, photo mean 117.1, gain 1.00. Percentiles were 55, 121 and 157 on screen and 57, 125 and 166 in the photo, so the remaining gap is mostly grain widening the highlights.

The new pipeline is also faster. Develop time went from 6.4 s to 5.1 s: decode 2.0 s, luma and rotate 0.6 s, grain 0.4 s, encode 1.5 s.

### Getting photos off the phone

- **AirDrop** needs iOS 7 or later.
- **iPhone OS 3 Mail** probably can't talk to today's mail servers.

So Silver has a **Share** screen. It shows a QR code for `http://<phone-ip>:8080/` and runs a small HTTP server: a BSD-sockets `accept` loop on a background thread. It only serves names it wrote itself, so `/p/../../etc/passwd.jpg` returns 404. The gallery page is written for today's Safari.

Verified from the Mac on the same Wi-Fi:
- `zbarimg` decodes the on-screen QR code as `http://192.168.145.232:8080/`;
- the gallery loads;
- a 762 KB photo downloads in 0.85 s.

Then the real test: from a modern iPhone on the apartment Wi-Fi, the gallery opened and showed both photos.

Not done yet: sharing over another iPhone's Personal Hotspot.

## Day 1: interface, round two

Feedback on the first interface:
- the moon shutter was too big and too busy for the chrome;
- "SILVER" didn't fit on the tarot card;
- GRID and SHARE should be symbols, not words;
- after the photo viewer and Share, DONE returned to the photo instead of the camera.

Changes (`app/Views.m`):
- **Shutter:** now 48 px and fits inside the 59 px bottom bar. It's a thin gold ring around a flat crescent: one disk with an offset disk removed by even-odd fill. A first attempt drew an empty ring because `CGContextClip` consumes the current path, so the clip has to come before adding the shapes.
- **Film card:** shows a symbol and a roman numeral instead of the name: I sun (SILVER), II new moon (COAL), III mist lines (MIST). The name stays in the top bar, now left-aligned.
- **Top bar:** grid and share are line-drawn icons that turn gold when active.
- **The bug:** opening Share now closes the viewer first.

Every change was checked from screenshots the app takes of itself (`silver://screenshot`).
