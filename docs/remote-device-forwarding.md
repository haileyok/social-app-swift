# Remote iPhone → Xcode forwarding (Linux laptop + remote Mac)

How to make an iPhone that is physically plugged into a **Linux laptop** appear as a
directly-attached device on a **remote macOS machine**, so Xcode can pair with it,
register its UDID, build, and install — with no physical access to the Mac.

Everything below is redacted: hostnames are placeholders (`<mac>`, `<laptop>`), and all
credentials are omitted.

## Why the obvious approaches fail

- **Tunneling the usbmuxd socket is not enough.** Xcode 15+ (through macOS 26 / Xcode 26)
  discovers and talks to tethered iOS devices through **CoreDevice (`remoted`)**, which
  uses the Mac's local USB stack (IOKit) — not `/var/run/usbmuxd`. A correct, working
  usbmuxd-over-ssh bridge (verified byte-for-byte with hand-rolled protocol probes)
  satisfies the *classic* MobileDevice stack but is invisible to `devicectl` and
  `xcodebuild -destination`. You must forward the **whole USB device**, not the
  usbmuxd protocol.
- **Free Apple developer accounts cannot register a device UDID via the web portal.**
  Registration happens automatically only when Xcode can see the device
  (`-allowProvisioningDeviceRegistration`).
- One-time Mac prerequisites: a GUI login session (VNC works), Xcode signed into the
  Apple ID, and the project's target set to the personal team (Signing & Capabilities →
  Team) so a development certificate exists.

## Architecture that worked

```
iPhone ─USB─ <laptop>
             └─ VirtualHere USB Server (generic Linux x86_64 build, trial = 1 device)
                  └─ TCP :7575 ──ssh -R──▶ <mac> loopback :7575
                        └─ VirtualHere Client (GUI app in the logged-in session)
                             └─ virtual IOUSBHostDevice in IOKit
                                  └─ remoted/CoreDevice → devicectl / xcodebuild
```

## Gotchas (each one cost real debugging time)

1. **Port + hostname must match what the server advertises.**
   Enumeration works against whatever manual hub address you configure, but *using* a
   device makes the client reconnect to the server's **advertised** `hostname:7575`.
   Forward `-R 7575:127.0.0.1:7575` (same port) and add `/etc/hosts` on the Mac:
   `127.0.0.1 <laptop-hostname>`. Symptom when wrong: `USE` returns `FAILED: API Timeout`
   with zero new lines in the server log.

2. **Free tier shares exactly one device.** An unlicensed VirtualHere server reports
   `max_devices=1`; any `USE` beyond the free device demands a license. Restrict the
   server so the iPhone is the only shared device:
   ```
   # server config file
   AllowedDevices=5ac/12a8        # <vid>/<pid>, hex, NO leading zeros
   sudo ./vhusbdx86_64 -c /path/to/config -r /path/to/server.log
   ```

3. **Stop and mask usbmuxd on the laptop.** It owns the iPhone's usbfs interfaces, so
   the VirtualHere server cannot claim/reset the device for capture:
   ```
   sudo systemctl stop usbmuxd && sudo systemctl mask usbmuxd
   ```

4. **THE EPERM FIX (the big one).** Attaching fails with
   `Error "Operation not permitted" (-1) trying to use this device`; the server log
   shows `BOUND` → `SURPRISE UNBOUND` within ~3 s, sometimes
   `Error -1 resetting device ... for capture`, and the iPhone re-enumerates
   (it leaves the bus and comes back). The fix is a **no-op reset handler registered
   on a freshly restarted client, in the literal placeholder form**:
   ```
   # 1) quit the client completely, relaunch it (e.g. open -a VirtualHere)
   # 2) register the handler via the control API, with LITERAL $...$ tokens:
   /Applications/VirtualHereUniversal.app/Contents/MacOS/VirtualHereUniversal \
       -t "CUSTOM EVENT,<device-address>,onReset.\$VENDOR_ID\$.\$PRODUCT_ID\$="
   # 3) then attach:
   ... -t "USE,<device-address>"
   ```
   Neither the resolved-ID form (`onReset.5ac.12a8=`) nor registering on a client that
   has already errored works — restart first, use the literal form, then USE.

5. **The client must be a GUI app in the logged-in session.** Launched from an ssh
   context (`nohup`) it hits IOKit `Operation not permitted`; running it as root does
   not help; the service mode (`-i`) requires a paid server license and refuses trial
   servers outright. Always `open -a VirtualHereUniversal --args -l /tmp/vhclient.log`.

6. **Logging and control API.** Server: `-r <file>`. Client: `-l <file>` (pass via
   `open --args`). Control API (`-t "<command>"`): `HELP`, `LIST`,
   `DEVICE INFO,<addr>`, `USE,<addr>`, `MANUAL HUB ADD,<host:port>`,
   `CUSTOM EVENT,<addr>,<handler>`.

7. **usbmuxd protocol trivia** (if anyone retries the socket-bridge path): the
   16-byte header is **little-endian** (length, version=1, message=8=plist, tag);
   a `ListDevices` plist must include `ClientVersionString`, `ProgName`, and
   `kLibUSBMuxVersion=3` or the daemon closes the connection silently. Ground truth
   for the byte format: `strace` of `idevice_id`.

8. **Pairing flow.** Once attached, `xcrun devicectl list devices` shows the phone as
   `available (pairing)`; CoreDevice then puts a Trust prompt on the phone — tap Trust
   (phone must be unlocked). State moves `connecting` → `connected (no DDI)`.

9. **First-build preparation.** `xcodebuild` may fail with
   `Device is busy (Preparing iPhone)` — first-connection prep (developer disk image
   mount / preparation). That is progress, not failure: wait, then re-run the build.
   Developer Mode (if off) is prompted on the phone; enabling it reboots the phone,
   after which the USB attach must be re-established (`USE` again).

10. **Mac housekeeping.** `launchd` owns `/var/run/usbmuxd`; SIP blocks
    `launchctl bootout` of the system usbmuxd. If you ever replace that socket with a
    bridge, a Mac reboot restores the stock USB stack.

## Reproduction checklist

**Laptop**
1. `sudo systemctl stop usbmuxd && sudo systemctl mask usbmuxd`
2. Server config with `AllowedDevices=5ac/12a8`; run `sudo ./vhusbdx86_64 -c <config> -r <log>`
3. `ssh -R 7575:127.0.0.1:7575 -N -o ServerAliveInterval=30 -o ExitOnForwardFailure=yes <user>@<mac>`

**Mac** (GUI session logged in)
4. `/etc/hosts`: `127.0.0.1 <laptop-hostname>`
5. Install + launch VirtualHere client: `open -a VirtualHereUniversal --args -l /tmp/vhclient.log`
6. `-t "MANUAL HUB ADD,127.0.0.1:7575"`
7. Quit client, relaunch, register the literal-form `onReset` handler (gotcha 4)
8. `-t "USE,<device-address>"`; verify with `ioreg -l | grep -i iphone` and
   `xcrun devicectl list devices`
9. Tap Trust on the (unlocked) phone
10. `xcodebuild -destination id=<UDID> -allowProvisioningUpdates -allowProvisioningDeviceRegistration build`
11. Handle `Preparing iPhone` (retry) and Developer Mode (enable, reboot, re-attach) prompts
12. Install/launch via `xcrun devicectl device install app --device <id> <path>.app`

## Failure-signature quick reference

| Symptom | Meaning |
| --- | --- |
| `USE` → `API Timeout 3 sec`, nothing in server log | client reconnecting to advertised host:port — fix tunnel/hosts (gotcha 1) |
| `IN USE BY: NO ONE` after OK | attach never started (stale hub entry / handler not registered) |
| Server: `BOUND` → `SURPRISE UNBOUND` ~3 s, device re-finds | missing literal-form `onReset` handler (gotcha 4) |
| Server: `Error -1 resetting device ... for capture` | device claimed elsewhere (usbmuxd) or reset quirk (gotchas 3, 4) |
| Client: `Operation not permitted (-1)` | wrong client context, or the reset-handler fix not applied yet |
| Client: `purchase a license` | service-mode client, or >1 shared device on trial server (gotcha 2) |
| `xcodebuild`: `Device is busy (Preparing iPhone)` | first-connection prep; wait and retry |
| `devicectl`: `available (pairing)` | tap Trust on the phone |
