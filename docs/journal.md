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

## Day 1: viewer, zoom and the film stocks

Feedback from using it in hand:
- opening a photo took a second or more;
- there was no pinch zoom;
- the thumbnail was square while the photos are 3:4;
- the stocks should be SILVER (default, medium contrast), ASH (faded, lower contrast) and HIGH CONTRAST.

**Opening faster.** `UIImage` decodes lazily, so the old viewer decoded the 1200×1600 JPEG on its first draw. The develop step now also writes a 400×533 screen copy, made with a 3×3 box filter in C (screen copy plus thumbnail: 286 ms). The viewer decodes that copy up front: `viewer opened SLV-20261115-224425 in 127 ms`.

**Zoom.** iPhone OS 3.1 has no gesture recognizers and no `scrollViewDidZoom:`. So the viewer is a `UIScrollView` subclass that re-centers its content in `layoutSubviews`, with an image view that counts taps itself: one tap closes, two taps zoom to 3×. When you zoom past 1×, the full 1200×1600 photo is decoded on a background thread (1093 ms) and swapped in. Pinch works through `UIScrollView`. For testing there's a `silver://zoom` command, which simulates a double tap in the middle of the photo.

**Memory ownership.** The develop step wraps its pixel buffers in `CGImage`s through a data provider with a free callback. `CGBitmapContextCreateImage` may share memory copy-on-write, which isn't safe once the buffer has been freed.

**Thumbnail:** now 33×44, the same 3:4 as the photos.

**Stocks:**

| # | Name | Character | Card symbol |
| --- | --- | --- | --- |
| I | SILVER | medium contrast | sun |
| II | ASH | blacks lifted to 10%, whites capped at 92%, almost no S-curve, lighter grain | haze lines |
| III | HIGH CONTRAST | full S-curve, slightly darker midtones (gamma 1.12), heavier grain | new moon |

## Day 1: borrowing Apple's photo browser

The homemade viewer's pinch zoom felt bad, and the phone already has a good photo browser. Silver saves every photo to the Camera Roll as well, so it can just borrow Apple's.

The class dump of `PhotoLibrary.framework` has the pieces:
- `PLCameraAlbum +sharedInstance` is the Camera Roll;
- `PLAlbumViewController -initWithAlbum:` is the thumbnail grid;
- `PLPhotoScrollerViewController -_initWithAlbum:lockStatusBar:currentImageIndex:` is the full-screen swipe, zoom and delete browser that the Photos app uses.

The grid only reports a tap through `-albumView:selectedPhoto:`, which only the image picker's subclass implements. So `app/Roll+System.m` builds a subclass at runtime (`objc_allocateClassPair`) that adds that one method and pushes the photo browser at the tapped index.

Two details:
- Passing `lockStatusBar:NO` made the browser show the status bar over its own navigation bar; `YES` fixes it.
- iPhone OS 3 has no `rootViewController`, so the navigation controller's view is added to the window and its appear and disappear calls are sent by hand.

The homemade viewer (`Viewer.m`) is deleted. The thumbnail opens the real Camera Roll grid with Apple's navigation bar, and the browser has Apple's zoom, swiping, toolbar and trash button.

Also in this round:
- The home-screen icon now matches the new shutter: a gold ring around a flat crescent.
- CamProbe is uninstalled from the phone. Its source stays in `probe/` as the record of the experiments.

## Day 1: one copy of every photo, saved like Apple's Camera app

Feedback:
- the status bar overlapped the Camera Roll's navigation bar;
- right after developing, the newest photo showed as black for about two seconds;
- and every photo was stored twice: once in Silver's own folder (full size, screen copy and thumbnail) and once in the Camera Roll through `UIImageWriteToSavedPhotosAlbum`.

**Saving the way the Camera app does.** Searching `PhotoLibrary` for code that uses the selector `addImage:withPreview:exifProperties:date:jpegData:notifyingTarget:selector:contextInfo:` turned up `PLSaveImageToCameraRollWithJPEGData`. Its disassembly is a one-line wrapper around `-[PLCameraAlbum addImage:…]`, with arguments in this order:
1. the image;
2. the preview (`nil` in the wrapper);
3. EXIF properties;
4. the date;
5. the JPEG bytes;
6. the target, selector and context to notify.

Silver now calls the method directly with its finished JPEG, the decoded full image and its 400×533 screen copy as the preview. The JPEG is written into DCIM untouched, with no second encode. Saving takes 140–167 ms. `+[PLCameraAlbum savePreviewWellImage:]` and `+previewWellImage` handle the shutter-side thumbnail, the same "image well" the Camera app uses.

**One copy.** `Library/Silver` is gone; the Camera Roll is the only store. The old folder's six photos were exact duplicates of `IMG_0027` to `IMG_0032`, so the folder was deleted. The develop step returns the JPEG and images in memory instead of writing files (`app/Develop.m`, with ImageIO helpers in `app/ImageIO.m`).

**Sharing the Camera Roll.** The share page now lists every JPEG in `/var/mobile/Media/DCIM/*/`, named like `100APPLE-IMG_0032`. The system's own thumbnails (`.MISC/IMG_xxxx.THM`) are only 75×75, too small for a modern phone. So the server makes 240-pixel thumbnails with `CGImageSourceCreateThumbnailAtIndex` (about 0.6 s each, since ImageIO decodes at reduced scale). A background thread makes them newest first as soon as Share opens, and keeps them in memory. Once they're made, the gallery loads in 0.13 s and each thumbnail in 0.06 s.

**Status bar.** `PLAlbumViewController` switches to a translucent status bar and lays out full screen under it. Silver now shows the status bar (`UIStatusBarStyleBlackTranslucent`) *before* the navigation controller lays out, so the bar sits below it as in the Photos app, and hides it again on Done.

Still to check with a lit scene: whether the newest photo now appears immediately in the browser. Every test shot in this round was taken face-down (preview mean 3.9).

## Day 1: a garbled viewfinder, softer grain and a real faded look

**The viewfinder glitch.** After taking a photo and browsing it in the Camera Roll, the viewfinder looked garbled. The screenshot showed the scene in bands, as if parts of it repeated. The log showed frames still arriving at 14.6 fps the whole time, and restarting the app fixed it. I couldn't reproduce it from the test hooks (shoot, open the roll, open the newest photo, close). So the changes aim at prevention, recovery and evidence:
- **Prevention:** the preview now stops while the Camera Roll is open (`CameraDeviceStopPreview`) and restarts when it closes. `CameraDeviceStartPreview` returns `0xe00002d5` until the in-flight captures have drained, so the resume retries every 100 ms. Restarting rebuilds the six capture surfaces. Nothing else is competing for the camera hardware while Apple's Photos code runs.
- **Evidence:** every camera event now logs the sensor state, using the MT9D112 variables `seq.mode`, `seq.state`, `ae.maxIndex`, `ae.index`, the preview size and window values, frame lines and line length. It also logs Camera.framework's state and in-flight capture count. Any frame whose surface isn't 304×400 with 1216 bytes per row is logged as an anomaly.
- **Recovery and a user-triggered dump:** touch and hold the viewfinder for 1.5 s. Silver saves the screen, the raw camera frame, the displayed frame, `camera.txt` (frame surface properties, the CameraDevice's six surfaces and free list, sensor state, fps and anomaly count) and a copy of the log into `~/Library/Logs/Silver/<time>/`. Then it restarts the preview and shows "DEBUG SAVED · RESTARTING". `silver://debug` does the same remotely.

**Grain** was too strong for an already-noisy 2 MP camera. The amplitude scale went from 0.5 to 0.28, so midtone grain in SILVER drops from about 12.6 to about 7 levels of standard deviation.

**ASH, take two.** "Lower contrast" isn't "faded". Faded prints have a milky veil over the shadows, while the midtones keep their contrast. The tone curve gained a `fade` parameter: a soft maximum with a gray floor, `0.5·(x + F + √((x − F)² + 0.12²))`, normalized so white stays white before the white point is applied. On a 9-point ramp (outputs 0–255):

| Input | 0 | 32 | 64 | 96 | 128 | 160 | 192 | 224 | 255 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| old ASH | 25 | 52 | 79 | 106 | 133 | 160 | 186 | 211 | 234 |
| new ASH | 59 | 61 | 66 | 86 | 121 | 157 | 191 | 219 | 237 |
| SILVER | 5 | 26 | 55 | 90 | 127 | 164 | 199 | 228 | 249 |

Everything from black to a quarter gray now lands on a milky 59–66, while the midtones are about as steep as SILVER's.

## Day 1: a share page that scales

From real use on an iPhone 17 Pro:
- a screenshot taken on the 2G didn't appear on the share page;
- with 40-odd photos, Safari gave up partway through loading the gallery.

**Screenshots.** iPhone OS 3 saves screenshots into the Camera Roll as PNG (`DCIM/100APPLE/IMG_0040.PNG`), and the server only listed `.JPG`. It now lists both and serves PNGs as `image/png`.

**Why Safari gave up.** The server handled one connection at a time. Every thumbnail not yet made took about 0.6 s, so Safari's parallel requests queued behind each other until they timed out. Now:
- **One thread per connection.** A slow thumbnail no longer holds up the page or other images.
- **Thumbnails are cached on disk** in `~/Library/Caches/Silver/thumbs/` (240 px JPEG, about 10 KB each), keyed by name and file size, so each is made only once ever. The rule is still one copy of every photo; these are a cache.
- **One thumbnail at a time.** A background thread works through the Camera Roll newest first while Share is open, behind a mutex. Memory on a 128 MB phone stays flat, and no two thumbnails compete for the CPU.
- **Instant placeholders.** Until a photo's thumbnail exists, the page gets the system's own 75×75 thumbnail (`.MISC/IMG_xxxx.THM`) with `Cache-Control: no-cache`, so it upgrades on the next visit. Finished thumbnails and full photos are sent with `max-age=86400`.
- **Pages of 60**, with Newer and Older links, so the page size doesn't grow with the Camera Roll.

Measured with 43 items in the Camera Roll:
- making every thumbnail the first time took 26.4 s in the background;
- after that, the gallery page loads in 0.13 s;
- fetching all 43 thumbnails six at a time, as Safari does, took 3.3 s.

## Day 1: release cleanup

Before release, a cleanup pass:
- **Comments:** cut from about 150 lines to 60, keeping only the non-obvious ones (private-API signatures, hardware quirks and gotchas like `CGContextClip` consuming the path).
- **Dead code:** removed an unused `on` state in `TextButton` and an unused `CSAccel` type.
- **Log size:** `/tmp/silver.log` now starts over once it passes 1 MB, since the live view logs a line every 2 s.
- **Version:** added a `CFBundleShortVersionString` of 1.0.
- **Phone address:** `scripts/phone` reads it from `IPHONE_HOST` or an untracked `.phone-host` file instead of a hard-coded LAN address.
- **README:** rewritten for people finding the repo.

The build is warning-free with `-Wall`.

## Day 1: sharing over a Personal Hotspot

With the 2G joined to the iPhone 17 Pro's Personal Hotspot, sharing works: the modern phone, acting as the hotspot, can reach the 2G's web server. That means photos can come off the phone anywhere, without Wi-Fi or a cable.

## Day 1: starting over with a clean jailbreak

The phone arrived already jailbroken. To make it ours, and to check that the install steps work from scratch, we erased it and jailbroke it again with [Legacy iOS Kit](https://github.com/LukeZGD/Legacy-iOS-Kit).

1. **Backup first.** All of `/private/var/{mobile,root,stash}` went to the Mac as a 117 MB tar over SSH. The Camera Roll's file list was checked against the phone: 43 of 43.
2. **Running the tool.** Legacy iOS Kit ran from a tmux session on the Mac. It needed the system's BSD `date` ahead of the GNU one on `PATH`. The options were `--jailbreak --ipsw-hacktivate --disable-actrec`. The last one is needed because the old phone had been hacktivated, so there was no activation record to save, and the tool stops if it can't find one.
3. **The restore.** The tool built a custom 3.1.3 image with Cydia, OpenSSH and hacktivation built in, put the phone into Recovery mode itself, and needed one manual DFU button sequence. The restore took about 7 minutes. The phone came back reporting `FactoryActivated`.
4. **First connection.** SSH over USB went through `iproxy 2222:22`; `scripts/phone` gained an `IPHONE_PORT` setting for it. Then `scripts/deploy` put Silver back, and the camera started on the clean system.

What we found afterward:
- **Melder.** The tool also installs Melder (`com.koutsie.melder`), "Package manager and root terminal", built for iPhone OS 3 to 13, as an alternative to Cydia.
- **Cydia's network errors were dead repos.** Cydia's first run re-adds its default repos, and three of them are gone:
  - `apt.modmyi.com` no longer resolves;
  - `cydia.zodttd.com` answers `308 Permanent Redirect`, presumably to HTTPS, which iPhone OS 3 can't speak;
  - `repo666.ultrasn0w.com` answers 404 or 410.

  saurik's repo, BigBoss and ios3.party all download fine over plain HTTP. The sources live in `CydiaSources` in `/var/mobile/Library/Preferences/com.saurik.Cydia.plist`, and `sources.list.d/cydia.list` is a symlink to a file Cydia regenerates from it. So the dead entries were removed from the plist itself.
- **"No SIM Card Installed".** Without a SIM, SpringBoard keeps showing this alert. Every alert-hiding package on BigBoss needs iOS 5 or later, so `tools/nosimalert` is a 15-line MobileSubstrate tweak. It swaps `-[SBAlertItemsController activateAlertItem:]` and drops `SBSIMLockAlertItem`s; both names come from SpringBoard's strings. It's built in the VM, signed with `ldid` and dropped into `/Library/MobileSubstrate/DynamicLibraries/` with a SpringBoard filter plist.
- **Home-screen wallpaper.** iPhone OS 3 only has lock-screen wallpaper, and even that is replaced by the battery picture while charging, which explained the earlier "black wallpaper" mystery. ios3.party's "iOS3 Wallpaper" package (`com.darlo770.wallpaper`) adds iOS 4-style home-screen wallpapers.

## Day 2: a proper icon, a volume-button shutter and a rotation lock

**Icon.**
- *Gloss.* Turning off `UIPrerenderedIcon` didn't make SpringBoard add the iOS 3 gloss and rounded corners; apparently that only happens for App Store apps, not ones installed in `/Applications`. So the icon draws them itself.
- *Position.* It still sat about 2 px lower than its neighbors. Cydia's `iconClassic.png`, Safari's `icon.png` and Melder's `IconClassic.png` are all 59×60, not 57×57: the 57×57 tile sits at (1, 0) with a 1 px margin on each side and a drop shadow underneath. Cydia's icon is an Apple "CgBI" PNG (raw deflate, BGRA, premultiplied); decoding it gave the shadow's opacity, 191 / 143 / 48 in the three rows below the tile. Silver's icon now uses the same 59×60 layout and shadow. Released as 1.1.

**Volume up as the shutter.** iPhone OS 3 sends apps no button events; the volume buttons belong to SpringBoard. Two private pieces make it work:
- *Detecting presses.* Celestial's `AVSystemController` posts `AVSystemController_SystemVolumeDidChangeNotification`. Silver treats an increase as a shutter press and immediately sets the volume back with `-setActiveCategoryVolumeTo:`. At maximum volume, up can't register a change, so Silver starts one notch below the top.
- *Hiding the volume pop-up.* `-[UIApplication setSystemVolumeHUDEnabled:]`, whose disassembly shows it calling SpringBoard's `SBSetSystemVolumeHUDEnabled`.
- *The pop-up on exit.* On leaving the app, re-enabling the pop-up and setting the volume, even to its current value, made SpringBoard flash its volume bar. Silver now only restores the volume if it actually changed.

**A crash that wasn't ours.** SpringBoard crashed twice. Both crash logs, one from before the volume shutter existed, show the same chain: a hardware event passes through Rotation Inhibitor into Activator 1.9.13, which calls a method iPhone OS 3 doesn't have (`-[NSObject doesNotRecognizeSelector:]`). Rotation Inhibitor 1.0.4 hard-requires Activator, and no repo still serves a period-correct Activator. So both were removed, along with FlipSwitch and RocketBootstrap, which only Activator used.

**Our own rotation lock** (`tools/rotationlock`) replaces them:
- *The lock.* A MobileSubstrate tweak loaded into every UIKit app. While locked, it drops `-[UIApplication deviceOrientationChanged:]`, the call GraphicsServices uses to deliver orientation changes.
- *The switch.* An SBSettings toggle (`isCapable`, `isEnabled`, `getStateFast`, `setState`, `getDelayTime`, the same exports as the toggle it replaces) writes a single `Locked` key to a preferences file.

**Stale thumbnail.** After deleting the newest photo in the Camera Roll, Silver's thumbnail still showed it, because it came from the Camera app's saved "image well" picture, which deletions don't update. The thumbnail now follows the Camera Roll itself. On launch and whenever the roll closes, a background thread makes a 120 px preview of the newest JPG or PNG in DCIM with ImageIO, which takes about half a second.
