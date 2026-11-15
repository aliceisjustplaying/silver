# Silver

**Silver** is a black-and-white camera app for the original iPhone (iPhone1,1) on iPhone OS 3.1.3 (jailbroken). It has a live B&W viewfinder at the camera's full 15 fps, film grain on photos and a Wi-Fi share page for the Camera Roll with a QR code. It uses the private `Camera.framework` C API and hand-written ARMv6 assembly.

## Code and scripts

- `app/`: the Silver app.
- `probe/`: the benchmark and experiment app (CamProbe), kept as the record of the experiments.
- `scripts/deploy`: builds Silver in the VM, signs it, installs it and launches it.
- `scripts/deploy-probe`: the same for CamProbe.
- `scripts/vm`: SSH into the build VM.
- `scripts/phone`: SSH into the phone.
- `tools/re/`: readers for the iOS 3 shared cache and an ARM disassembler.

## Status

- **Working on the phone:** live B&W preview at about 14.6 fps (10 ms of work per frame), three film stocks (SILVER, ASH, HIGH CONTRAST), grain on the photo, brightness matched to the viewfinder, thirds grid, photos saved straight into the Camera Roll the way the Camera app does it, and browsed with the system Photos UI (the private PhotoLibrary framework) and the Wi-Fi share page.
- **Sharing:** tested from a modern iPhone on the same Wi-Fi network.
- **Not tested yet:** sharing over a Personal Hotspot, and the preview frame rate in dim light.

## Docs

- [docs/journal.md](docs/journal.md): the story so far, with dead ends and measurements.
- [docs/build-vm.md](docs/build-vm.md): the Snow Leopard and Xcode 3.2.6 build VM, with SSH and SMB access.
- [docs/private-camera-re.md](docs/private-camera-re.md): how the live camera frames were found, with addresses, signatures and benchmarks.

## License

MIT (see [LICENSE](LICENSE)). `app/vendor/qrcodegen.[ch]` is Project Nayuki's QR Code generator library, also MIT.
