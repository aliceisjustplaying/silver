# Build VM

The app is built with Xcode 3.2.6 in a Mac OS X 10.6.8 (Snow Leopard) VM. The target is an original iPhone (2G) on iPhone OS 3.1.3, jailbroken, with Cydia.

## VM

- Runs in Virtual Intel Mac (QEMU, `qemu-system-x86_64` with TCG emulation) on an Apple Silicon host.
- Snow Leopard 10.6.8 (`10K549`), 4 CPUs, 8 GB RAM, 128 GB disk.
- VM user: `alice`.
- Networking is QEMU user-mode (slirp). The VM app sets these port forwards:

  ```
  hostfwd=tcp:127.0.0.1:2223-:22    # SSH
  hostfwd=tcp:127.0.0.1:1446-:445   # SMB
  ```

- From inside the VM, `10.0.2.2` reaches the host's loopback interface.

## SSH (host → VM)

`scripts/vm` runs SSH into the VM:

```sh
scripts/vm                 # interactive shell
scripts/vm 'xcodebuild -version'
```

The VM runs OpenSSH 5.2, which offers only `ssh-rsa` and `ssh-dss` host keys and doesn't support ed25519 keys. So the script:

- uses a dedicated RSA key, `~/.ssh/snowleopard_vm`, whose public half is in the VM's `~/.ssh/authorized_keys`;
- re-enables `ssh-rsa` with `HostKeyAlgorithms=+ssh-rsa` and `PubkeyAcceptedAlgorithms=+ssh-rsa`;
- keeps the VM's host key in `~/.ssh/known_hosts_snowleopard_vm`.

How the key was installed: the host served `snowleopard_vm.pub` with `python3 -m http.server --bind 127.0.0.1`, and the VM fetched it with `curl http://10.0.2.2:<port>/key.pub >> ~/.ssh/authorized_keys`.

One fix was needed in the VM:

- **Home folder permissions.** Turning on File Sharing had made `/Users/alice` world-writable (`drwxrwxrwx+`). sshd's `StrictModes` then refused the key (`/var/log/secure.log`: `Authentication refused: bad ownership or modes for directory /Users/alice`). Fixed with `chmod 755 ~`.

`sudo` over SSH needs a password (`/etc/sudoers` is unchanged). A `sudo` in the VM's Terminal leaves a timestamp that lets SSH sessions run `sudo` for a few minutes afterward.

## SMB

### VM → host: not possible

Snow Leopard's SMB client only speaks SMB1. The host's SMB server drops the connection on an SMB1 `NEGOTIATE` without replying.

### Host → VM: works, with one change

Mount the VM's home folder from the host:

```sh
mount_smbfs //alice@127.0.0.1:1446/alice <mountpoint>
```

In Finder (⌘K), the URL is `smb://alice@127.0.0.1:1446/alice`. Leaving out `:1446` connects to the host's own SMB server on port 445 instead.

The VM side:

- SMB file sharing is enabled for `alice` (`pwpolicy -u alice -gethashtypes` lists `SMB-NT`).
- The share is `/Users/alice`, named `alice`.
- The host's SMB client still allows SMB1 (`protocol_vers_map` defaults to `7` per `man nsmb.conf`).

Logins first failed before the password was ever checked. The VM's Samba (`3.0.28a-apple`) can't parse the SPNEGO login token from the current macOS SMB client. With debug logging, `/var/log/samba/log.smbd` showed:

```
spnego_parse_auth failed at 396
... cmd=115 (SMBsesssetupX) NT_STATUS_LOGON_FAILURE
```

The fix was to turn SPNEGO off in the VM's Samba. This was appended after the "Site-specific parameters can be added below this comment." line in `/etc/smb.conf`:

```
[global]
    use spnego = no
```

followed by a reload:

```sh
sudo smbcontrol smbd reload-config
```

The original file is saved at `/etc/smb.conf.orig`. Samba's other generated settings live in `/var/db/smb.conf`, which `smb-sync-preferences` regenerates. Don't edit that file.

To raise Samba logging until the next smbd restart: `sudo smbcontrol smbd debug 5`.

## Installing Xcode 3.2.6

The installer image is `xcode_3.2.6_and_ios_sdk_4.3.dmg`. Installing it with the clock at the real date fails with "An unknown installation error occurred". `/var/log/install.log` gives the cause:

```
Failed install preflight: ... "The package “iPhoneSDKTools.pkg” is untrusted." ... CSSMERR_TP_CERT_EXPIRED
```

The certificate that signed the packages has expired, so the fix is to set the VM's clock back to 2011 for the install.
