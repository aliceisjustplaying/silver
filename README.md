# iphone-2g-camera

A camera app with live filters for the original iPhone (2G) on iPhone OS 3.1.3 (jailbroken). It uses the private `PhotoLibrary` framework (`PLCameraController`), because the public live-camera APIs need iOS 4.

- [docs/build-vm.md](docs/build-vm.md): the Snow Leopard and Xcode 3.2.6 build VM, with SSH and SMB access from the host.
- [docs/private-camera-re.md](docs/private-camera-re.md): how to get live camera frames on 3.1.3 (reverse engineering).
- `scripts/vm`: SSH into the build VM.
- `tools/re/`: scripts for reading the iOS 3 shared cache.
