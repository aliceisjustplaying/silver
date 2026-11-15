# iphone-2g-camera

**Silver** is a black-and-white camera app for the original iPhone (iPhone1,1) on iPhone OS 3.1.3 (jailbroken). It has a live B&W viewfinder at the camera's full 15 fps, film grain on photos and a Wi-Fi share page with a QR code. It uses the private `Camera.framework` C API and hand-written ARMv6 assembly.

## Code and scripts

- `app/`: the Silver app.
- `probe/`: the benchmark and experiment app (CamProbe).
- `scripts/deploy`: builds Silver in the VM, signs it, installs it and launches it.
- `scripts/deploy-probe`: the same for CamProbe.
- `scripts/vm`: SSH into the build VM.
- `scripts/phone`: SSH into the phone.
- `tools/re/`: readers for the iOS 3 shared cache and an ARM disassembler.

## Docs

- [docs/journal.md](docs/journal.md): the story so far, with dead ends and measurements.
- [docs/build-vm.md](docs/build-vm.md): the Snow Leopard and Xcode 3.2.6 build VM, with SSH and SMB access.
- [docs/private-camera-re.md](docs/private-camera-re.md): how the live camera frames were found, with addresses, signatures and benchmarks.
