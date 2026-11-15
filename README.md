# Silver

Silver is a black-and-white camera app for the original iPhone (2007, iPhone1,1) running iPhone OS 3.1.3, jailbroken.

- **Live B&W viewfinder** at the camera's full frame rate, about 15 fps.
- **Three film stocks:** SILVER (medium contrast), ASH (faded) and HIGH CONTRAST. The viewfinder shows the stock's tone curve live.
- **Film grain** added to each photo after it's taken, with brightness matched to the viewfinder.
- **Camera Roll:** photos are saved straight into it, the same way Apple's Camera app does, and the thumbnail opens the system Camera Roll and photo browser.
- **Share over Wi-Fi:** a QR code opens a gallery of the Camera Roll in any phone's browser on the same network, so you can save photos without a cable.

iPhone OS 3 has no public way to read live camera frames; that came with iOS 4. Silver uses `Camera.framework`, a private C API left over from iPhone OS 2. A hand-written ARMv6 assembly loop converts each frame to gray. The private `PhotoLibrary` framework provides the Camera Roll integration. [docs/journal.md](docs/journal.md) tells the whole story.

## Requirements

- An original iPhone on iPhone OS 3.1.3, jailbroken, with OpenSSH (from Cydia). Other models and firmware versions are untested. The camera code expects this phone's sensor and Camera.framework's internal layout, which are specific to 3.1.3.
- To build: Mac OS X 10.6 with Xcode 3.2.6 and the iOS 4.3 SDK. A virtual machine works; [docs/build-vm.md](docs/build-vm.md) describes the setup used here.
- `ldid` to fake-sign the binary (on the build machine or any Mac). The phone's own `codesign_allocate` rejects Xcode 3.2.6 binaries.

## Build and install

Build `app/` with `make` on the 10.6 machine. That produces `Silver.app`. Then:

1. Run `ldid -S Silver.app/Silver`.
2. Copy `Silver.app` to `/Applications/` on the phone.
3. Run `su mobile -c uicache` on the phone so the icon appears.

`scripts/deploy` does all of this and launches the app. It assumes the VM and keys described in [docs/build-vm.md](docs/build-vm.md), `ldid` from nixpkgs, and the phone's address in `IPHONE_HOST` or in an untracked `.phone-host` file.

## Using it

| Control | What it does |
| --- | --- |
| Gold moon | Takes a photo. Developing takes about 5 s, and the viewfinder keeps running. |
| Card (bottom right) or stock name (top left) | Switches film stock. |
| Grid icon | Toggles a thirds grid. Silver remembers the grid and the stock. |
| Thumbnail | Opens the Camera Roll. |
| Share icon | Shows a QR code for `http://<phone>:8080/`. Scan it from another phone on the same Wi-Fi, or with the iPhone joined to that phone's Personal Hotspot. The page lists the whole Camera Roll, including screenshots, 60 per page. The server runs only while this screen is open. |
| Touch and hold the viewfinder | Saves debug information to `~/Library/Logs/Silver/<time>/` on the phone and restarts the preview. Use it if the viewfinder ever looks wrong. |

The running log is `/tmp/silver.log`. For development, the app also accepts `silver://` URLs: `shutter`, `stock`, `grid`, `share`, `unshare`, `roll`, `rollphoto`, `unroll`, `debug` and `screenshot`. For example, `su mobile -c "uiopen silver://shutter"` over SSH.

## Repository

| Path | Contents |
| --- | --- |
| `app/` | Silver |
| `probe/` | CamProbe, the experiment app behind the measurements in the docs |
| `scripts/` | deploy, plus SSH helpers for the build VM and the phone |
| `tools/re/` | readers for the iPhone OS 3 shared library cache and an ARM disassembler |
| `tools/battery/` | dumps the phone's power-source registry properties |
| `docs/journal.md` | the build log, with dead ends and measurements |
| `docs/private-camera-re.md` | reverse engineering of the camera path |
| `docs/build-vm.md` | the build VM |

## License

MIT, see [LICENSE](LICENSE). `app/vendor/qrcodegen.[ch]` is Project Nayuki's QR Code generator, also MIT.
