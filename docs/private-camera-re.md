# Live camera frames on iPhone OS 3.1.3 (iPhone1,1)

This document records static reverse engineering of the real 3.1.3 (7E18) firmware for the original iPhone. Its goal is to find a way for our app to get CPU-readable live preview frames at the camera's own rate.

**Recommendation:** use the private C API in `Camera.framework`. It opens the camera sensor in our own process. It then delivers each preview frame to a callback on our run loop as a 304×400 BGRA `CoreSurfaceBuffer`, which we can lock and read directly. This doesn't involve `AVCapture`, `PLCameraController`, mediaserverd or screen grabs.

Everything under "Verified" was read from the disassembly. Anything marked *inferred* or listed under open questions needs the device.

## Method

1. **Firmware.** `iPhone1,1_3.1.3_7E18_Restore.ipsw` came from Apple's CDN. The URL is listed by `https://api.ipsw.me/v4/device/iPhone1,1?type=ipsw`.
2. **Decryption.** The root filesystem is `018-6482-014.dmg`. It was decrypted with the published RootFS key from `https://api.ipsw.me/v4/keys/ipsw/iPhone1,1/7E18`, using `tools/re/vfdecrypt.py` (FileVault v2: AES-128-CBC per 4096-byte chunk, with the IV from HMAC-SHA1 of the chunk number). The result was mounted with `hdiutil`.
3. **Shared cache.** System libraries live in `System/Library/Caches/com.apple.dyld/dyld_shared_cache_armv6` (format `dyld_v1   armv6`). Three existing tools failed on it:
   - `ipsw dyld info` fails with `failed to parse cache ... EOF`;
   - radare2's extractor produces 0 files;
   - KennyTM's `dyld_decache`, built for arm64, writes corrupted Mach-O headers.

   `tools/re/dsc.py` instead reads the cache in place: images, load commands, symbol tables, stubs and Objective-C 2 class, method and ivar lists. `tools/re/armdis.py` disassembles with Capstone and annotates symbols and stubs. `tools/re/dump.py` prints class dumps.
4. **Local copies.** The cache, the class dumps (`.re/PhotoLibrary.classes.txt`, `.re/Celestial.classes.txt`) and the full Camera.framework disassembly (`.re/Camera.framework.s`) are in `.re/`. That directory is git-ignored, because those are Apple binaries or derived from them.

## Other findings

- **Graphics.** The only OpenGL ES engine is `System/Library/Frameworks/OpenGLES.framework/MBXGLEngine.bundle`, so the phone has OpenGL ES 1.1 only and no shaders. There's also a private `MBX2D.framework` (a 2D blitter, with `mbx2DCreateSurface`, `mbxWrapSurface` and `mbxGetCoreSurfaceID`).
- **How Apple's camera works on 3.1.3.** `PLCameraController` (PhotoLibrary) holds an `AVCapture` (Celestial), whose `_priv` holds an `OpaqueFigRecorder`. Celestial exports both `FigRecorderCreate` and a `FigRecorderRemoteClient_*` and `FigRecorderRemoteServer_*` pair, so the recorder can run out of process. Frames come from `H1ISP.mediacapture` (`H1ISPCaptureDeviceCreate`, `FigH1ISPCameraCaptureStreamStart`), which imports `IOSurfaceAcceleratorCaptureSurface`. Celestial shows them through `CAImageQueueCreate` on `AVCapture._videoPreviewLayer` (a `CALayer`).
- **That path is hard to tap.** Reading frames from it would mean hooking into a Core Animation image queue that may be fed from another process. Hence the recommendation above.
- **Camera.framework predates it.** It's the older direct-to-sensor API. In 3.1.3 both `PhotoLibrary` and `H1ISP.mediacapture` still list it as a load command, but neither imports any `CameraDevice*` function.

## Verified: the Camera.framework API

All addresses are in the 3.1.3 iPhone1,1 shared cache. The framework's text runs from `0x33e06da8` to `0x33e08648`.

### `CameraDeviceCreate(CFAllocatorRef alloc, void *unused, CameraDeviceRef *out)` at `0x33e07ce4`

It does the following, in order:

1. `IOMasterPort`, then `IOServiceMatching("IOCameraSensor")`, `IOServiceGetMatchingServices` and `IOServiceOpen(service, mach_task_self, 0, &connect)`.
2. Creates a CF instance of 0xAC bytes and sets these fields:
   - preview `+0x3c = 304` and `+0x40 = 400` (`0x130` and `0x190`);
   - photo `1600 × 1200` (`0x640` and `0x4b0`);
   - the user-client connection at `+0xac`.
3. Ends with `CoreSurfaceAcceleratorCreate(alloc, 0, dev + 0x54)`.

On failure it returns `0xe00002c0`, printing `"%s: Couldn't find any IOCameraSensor devices."`, or `0xe00002bd`. On success it returns `0`.

The second argument is never read: `r1` is overwritten by the `IOMasterPort` call.

### Setters

These are plain stores:

| Function | Address | Effect |
| --- | --- | --- |
| `CameraDeviceSetClient(dev, cb, refcon)` | `0x33e06ddc` | `dev+0x94 = cb`, `dev+0x98 = refcon` |
| `CameraDeviceSetCaptureCallback(dev, cb, refcon)` | `0x33e06de8` | `dev+0x9c = cb`, `dev+0xa0 = refcon` (photo callback) |
| `CameraDeviceSetImageQueueHelper(dev, helper)` | `0x33e06df4` | `dev+0x8c` |
| `CameraDeviceSetProperties` | `0x33e06dd4` | returns `0` and does nothing, so preview size can't be changed |

### `CameraDeviceScheduleWithRunLoop(dev, CFRunLoopRef rl, CFStringRef mode)` at `0x33e06e28`

Adds `CoreSurfaceAcceleratorGetRunLoopSource(dev+0x54)` to the run loop. **Callbacks only fire on that run loop.**

### `CameraDeviceStartPreview(dev)` at `0x33e07610`

1. Allocates 6 surfaces with `CreateBGRABuffer(304, 400)` into `dev+0x58…0x6c` and puts each on the free list at `dev+0x70…0x84`.
2. Queues 6 captures with `CapturePreviewSurface`.
3. Calls the client with `cb(dev, 1, NULL, refcon)`.
4. Sets state `dev+0xa4 = 1`.

It returns `0xe00002d5` if already started.

### `CreateBGRABuffer(w, h)` at `0x33e070fc` (internal)

Calls `CoreSurfaceBufferCreate` with these properties:

- memory region `"PurpleGfxMem"`;
- pixel format `0x42475241` (`'BGRA'`), 4 bytes per element;
- width `w`, height `h`;
- bytes per row `((w + 15) & ~15) * 4`, which is **1216** for 304;
- allocation size `bytesPerRow * ((h + 15) & ~15)`.

### `CapturePreviewSurface(dev)` at `0x33e07000` (internal)

Takes a free surface and calls `CoreSurfaceAcceleratorCaptureSurface(accel, surface, opts, 0, …)`. The stack arguments are a rectangle `{400, 304, 0, 0, 400, 304}` (the sensor is landscape), then the completion `CameraDeviceCaptureCallback`, refcon `dev`, then `surface`. It increments the in-flight count at `dev+0xa8`.

### `CameraDeviceCaptureCallback(dev, status, surface, …)` at `0x33e07810`

This is the accelerator's completion handler. In preview state, when `status == 0` and `state == 1`, it calls:

```
client(dev, status + 8 /* = 8 */, surface, refcon)   // r0..r3
```

and then immediately queues another capture with `CapturePreviewSurface(dev)`. It doesn't recycle the surface it just handed out.

### `CameraDeviceRecycleSurface(dev, surface)` at `0x33e0774c`

`PutSurface` returns the surface to the free list. In preview state it then queues another capture. **The client must call this for every frame.** With 6 surfaces and none returned, the stream stops after 6 frames.

### `CameraDeviceStopPreview(dev)` at `0x33e07520`

Sets state 2 and, once in-flight captures drain, calls `cb(dev, 2, NULL, refcon)`.

### `CameraDeviceTakePhoto(dev)` at `0x33e07258`

Captures a 1600×1200 still and compresses it with the hardware JPEG encoder (`JPEGCompressSurface` through the `AppleJPEGDriver` user client). It then calls the photo callback:

```
cb(dev, 0x20, CFDataRef jpeg, CFDictionaryRef captureProperties, CGImageRef thumb400x300, refcon)
```

The registers are `r0`–`r3`, then stack word 0 (the thumbnail) and stack word 1 (`refcon`). Afterward the photo surface is recycled and preview resumes.

The argument positions and the 400×300 BGRA thumbnail are verified. That `r2` is the JPEG `CFData` is *inferred*: it's the out-parameter that `JPEGCompressSurface` fills. That `r3` is the capture-properties dictionary is also *inferred*: it comes from `CoreSurfaceBufferCopyProperty` on the photo surface, and `"CaptureProperties"` is in the framework's strings. If `JPEGCompressSurface` returns 0, the callback gets `NULL` for the data, the properties and the thumbnail.

### Client event codes

These are read from the calls above:

| Code | Meaning | `surface` argument |
| --- | --- | --- |
| `1` | preview started | `NULL` |
| `2` | preview stopped | `NULL` |
| `8` | preview frame | 304×400 BGRA `CoreSurfaceBufferRef` |

## Sketch

This targets our app: Xcode 3.2.6, iOS SDK 4.3, armv6, deployment target 3.1. Link `Camera.framework` and `CoreSurface.framework` from the device's `/System/Library/PrivateFrameworks`, or resolve the functions with `dlsym`.

```objc
typedef struct __CameraDevice *CameraDeviceRef;
typedef void *CoreSurfaceBufferRef;
typedef void (*CameraDeviceClientCallback)(CameraDeviceRef dev, int event,
                                           CoreSurfaceBufferRef surface, void *refcon);
extern int  CameraDeviceCreate(CFAllocatorRef alloc, void *unused, CameraDeviceRef *out);
extern void CameraDeviceSetClient(CameraDeviceRef, CameraDeviceClientCallback, void *refcon);
extern void CameraDeviceScheduleWithRunLoop(CameraDeviceRef, CFRunLoopRef, CFStringRef mode);
extern int  CameraDeviceStartPreview(CameraDeviceRef);
extern int  CameraDeviceStopPreview(CameraDeviceRef);
extern int  CameraDeviceRecycleSurface(CameraDeviceRef, CoreSurfaceBufferRef);
extern int    CoreSurfaceBufferLock(CoreSurfaceBufferRef, unsigned flags);   // Camera.framework passes 3
extern int    CoreSurfaceBufferUnlock(CoreSurfaceBufferRef, unsigned flags);
extern void  *CoreSurfaceBufferGetBaseAddress(CoreSurfaceBufferRef);
extern size_t CoreSurfaceBufferGetBytesPerRow(CoreSurfaceBufferRef);
extern size_t CoreSurfaceBufferGetWidth(CoreSurfaceBufferRef);
extern size_t CoreSurfaceBufferGetHeight(CoreSurfaceBufferRef);

static void onCamera(CameraDeviceRef dev, int event, CoreSurfaceBufferRef s, void *refcon) {
    if (event != 8 || !s) return;
    if (CoreSurfaceBufferLock(s, 3) == 0) {
        uint8_t *bgra = CoreSurfaceBufferGetBaseAddress(s);   // 304 x 400, 1216 bytes/row
        size_t rowBytes = CoreSurfaceBufferGetBytesPerRow(s);
        FilterAndPresent(bgra, CoreSurfaceBufferGetWidth(s), CoreSurfaceBufferGetHeight(s), rowBytes, refcon);
        CoreSurfaceBufferUnlock(s, 3);
    }
    CameraDeviceRecycleSurface(dev, s);   // required, or preview stalls after 6 frames
}

// setup, on the main thread:
CameraDeviceRef cam = NULL;
if (CameraDeviceCreate(kCFAllocatorDefault, NULL, &cam) == 0) {
    CameraDeviceSetClient(cam, onCamera, self);
    CameraDeviceScheduleWithRunLoop(cam, CFRunLoopGetCurrent(), kCFRunLoopCommonModes);
    CameraDeviceStartPreview(cam);
}
```

`FilterAndPresent` stands for the filter pipeline, written separately. Example: copy into a 512×512 RGBA texture with `glTexSubImage2D` and filter with `GL_COMBINE`, or run a CPU lookup table first.

## Open questions only the device can answer

1. **Permission.** Can a jailbroken app (in `/Applications`, running as `mobile`, not sandboxed) open the `IOCameraSensor` user client? Does it collide with mediaserverd if `AVCapture` was used earlier in the session? `IOServiceOpen` returns its error, and `CameraDeviceCreate` returns `0xe00002c0` if no service matches.
2. **Frame rate.** Measure it by timestamping event 8. Cycorder on this hardware reported 6–15 fps depending on light. `CameraDeviceGetPropertiesCopy` (`0x33e06f48`) exposes `PreviewMaxFPS` and `PreviewCurrentFPS` keys, but their values weren't decoded.
3. **Read speed.** The buffers come from the `"PurpleGfxMem"` region. If that memory isn't cached for CPU reads, reading pixels will be slow. A 304×400×4 frame is about 486 KB, so per-frame copy time needs to be measured.
4. **Orientation and colors.** Confirm that the frame is portrait 304×400 and that the BGRA channel order shows correct colors. *Inferred:* the sensor rectangle is 400×304 landscape and the buffer is created 304 wide by 400 high, so the accelerator rotates.
5. **Run-loop requirement.** *Inferred:* events arrive only after `CameraDeviceScheduleWithRunLoop`, because the accelerator's run-loop source is the only route to `CameraDeviceCaptureCallback`.
