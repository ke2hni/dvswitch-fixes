# 🛠️ DVSwitch Server & Dashboard Fix Pack

<p align="center">
  <img src="https://img.shields.io/badge/DVSwitch-Fix%20Pack-2563eb?style=for-the-badge">
  <img src="https://img.shields.io/badge/ASL3-Compatible-success?style=for-the-badge">
  <img src="https://img.shields.io/badge/Raspberry%20Pi-ARM64-c51a4a?style=for-the-badge&logo=raspberrypi">
  <img src="https://img.shields.io/badge/Debian%2012-Bookworm-orange?style=for-the-badge&logo=debian">
  <img src="https://img.shields.io/badge/Debian%2013-Trixie-red?style=for-the-badge&logo=debian">
</p>

<p align="center">
  Tested on <strong>node68425</strong> · <strong>KE2HNI</strong> · Raspberry Pi 5 · ASL3 / DVSwitch
</p>

---

## 📌 Overview

This repository collects a set of confirmed DVSwitch Server and stock DVSwitch Dashboard repairs developed while troubleshooting a fresh ASL3/DVSwitch installation.

The fixes address several problems that can otherwise look unrelated:

```text
YSF five-digit reflector numbers truncated to four digits
YSFGateway "Invalid YSF reflector id/name" errors
YSF Network dashboard box displaying null
P25 connected but dashboard still showing Unlinked
D-Star dashboard displaying Tx TG 0 instead of REF/module
Stale or failed DVSwitch host and talkgroup database downloads
RX Monitor button green but no browser audio
Gateway INI files containing obsolete or unsupported settings
```

Each repair was tested incrementally on the live node before being marked working. The six files in this repository are the **core functional repair set**. Responsive-layout and dark-mode projects are intentionally maintained separately.

> [!IMPORTANT]
> These files are not a universal blind-replacement package. Read the compatibility and installation notes for each file. Always create backups first.

---

## 🔎 Problems and Search Terms

This section intentionally includes exact symptoms and log messages so other users can find the project when searching for the same DVSwitch problems.

### YSF reflector will not connect by number

Common symptoms:

```text
DVSwitch YSF 5 digit reflector not working
ex. YSFGateway 44444 becomes 4444
ex. YSFGateway 53594 becomes 3594
Trying to find non existent YSF reflector with an id of 4444
Invalid YSF reflector id/name - "4444"
DVSwitch YSF PTT but no audio
YSF works by IP address but not reflector number
DVSwitch dashboard YSF master null
P25 tune sets Tx TG/Ref but P25 Net remains Not Linked
P25 reflector only connects after pressing PTT
P25 five digit reflector 10400 becomes 400
P25 TalkGroup missing space
P25 linked announcement starts during PTT
```

Root cause on the tested ARM64 build:

```text
Broken command: LinkYSF44444
Correct command: LinkYSF 44444
```

The missing separator caused YSFGateway to parse the reflector number incorrectly. The patched ARM64 `MMDVM_Bridge` binary sends the correct command.

### P25 tune does not connect until PTT

Common symptoms:

```text
DVSwitch P25 tune does not connect
P25 Net remains Not Linked after dvswitch.sh tune
Analog Bridge shows Tx TG/Ref but P25Gateway is unlinked
P25 only connects after pressing PTT
P25 five digit reflector number loses first digit
tune 10400 connects to reflector 400
TalkGroup10201 missing separator
P25 linked announcement clipped after PTT
```

Root cause on the tested ARM64 build:

```text
Broken command: TalkGroup10201
Correct command: TalkGroup 10201
```

`dvswitch.sh tune` correctly passed `txTg=10201` through Analog_Bridge, but the installed MMDVM_Bridge binary emitted the remote command without the separator expected by P25Gateway. P25Gateway consequently parsed five-digit targets one digit short. For example, `10400` became `400`; `10201` became `201` and caused an unlink when reflector 201 was unavailable.

PTT appeared to repair the connection because the P25 voice frames carry the complete numeric talkgroup and bypass the malformed text command. This also caused the queued “Linked to…” prompt to start at the end of the triggering PTT, clipping the beginning of the announcement.

The patched ARM64 `MMDVM_Bridge` binary sends the corrected command with a space. Live testing confirmed that `dvswitch.sh tune 10200` and `dvswitch.sh tune 10201` linked immediately by remote command and updated both the Analog Bridge and P25 Net dashboard boxes without PTT or a page refresh.

> [!NOTE]
> The direct P25 linking defect is fixed. A separate P25Gateway voice-prompt timing issue remains: this P25Gateway build queues the spoken link prompt until it receives a P25 end-of-transmission frame. The dashboard and network link update immediately, but the HT may remain silent until the first PTT and then hear a clipped announcement. Correcting that separate behavior requires a P25Gateway source change, not another MMDVM_Bridge format-string patch.

### P25 connected but dashboard says Unlinked

Common symptoms:

```text
DVSwitch P25 dashboard Unlinked
P25Gateway Switched to reflector but dashboard not connected
Switched to reflector #####
P25 audio works but DVSwitch dashboard does not show link
```

The stock dashboard parser did not recognize the installed P25Gateway log wording. The updated `functions.php` accepts `Switched to reflector #####` and includes `Switched` messages in the filtered log data.

### YSF dashboard displays null

Common symptoms:

```text
DVSwitch YSF Network null
YSF reflector connected but dashboard shows null
YSFHosts case sensitive reflector match
DVSwitch YSF linked but reflector name missing
```

The updated `status.php` performs case-insensitive YSF reflector matching and provides a safe linked-target fallback instead of displaying `null`.

### D-Star dashboard displays TG 0

Common symptoms:

```text
DVSwitch D-Star Tx TG 0
DVSwitch dashboard does not show D-Star reflector
REF030 C missing from Analog Bridge information
D-Star connected but dashboard only displays talkgroup zero
```

The updated `status.php` displays the D-Star reflector and module, such as `REF030 C`, rather than the internal talkgroup value `0`.

### RX Monitor turns green but has no sound

Common symptoms:

```text
DVSwitch RX Monitor no audio
DVSwitch dashboard RX Monitor green but no sound
WebSocket port 8080 blocked
Web Proxy 8080 2222
PCM client listening on port 2222
DVSwitch browser speaker audio not working
```

On the tested installation, Analog_Bridge correctly sent 8 kHz, 16-bit mono PCM to UDP port `2222`, but the browser could not establish the WebSocket connection because TCP port `8080` was missing from the active firewalld zone.

After allowing TCP `8080` and rebooting, RX Monitor playback was confirmed at approximately `49.8` 320-byte PCM packets per second.

No changes to `Analog_Bridge.ini`, `proxy.js`, or `pcm-player.min.js` were required.

---

## 📦 Included Core Repair Files

| Repository file | Installed path | Purpose |
| --- | --- | --- |
| `dvswitch.sh` | `/opt/MMDVM_Bridge/dvswitch.sh` | Reliable, validated network database updates |
| `MMDVM_Bridge` | `/opt/MMDVM_Bridge/MMDVM_Bridge` | ARM64 five-digit YSF and P25 remote-tuning repairs |
| `P25Gateway.ini` | `/opt/P25Gateway/P25Gateway.ini` | Configuration aligned with the installed P25Gateway binary |
| `YSFGateway.ini` | `/opt/YSFGateway/YSFGateway.ini` | Configuration aligned with YSFGateway 20211108 |
| `functions.php` | `/usr/share/dvswitch/include/functions.php` | P25 link-status parsing and log filtering |
| `status.php` | `/usr/share/dvswitch/include/status.php` | YSF null fix, Tx TG/Ref label, and D-Star reflector display |

---

## ✨ Fix Details

### 1. Validated DVSwitch database updates

`dvswitch.sh` confirmed version:

```text
1.6.4
```

The script replaces unreliable or outdated database downloads with validated sources for the supported network data. It checks downloaded content before replacing the working file and preserves the existing database when a download is empty, invalid, HTML, or otherwise unusable.

Confirmed network data includes:

* NXDN reflectors
* P25 reflectors
* YSF reflectors
* BrandMeister talkgroups
* TGIF talkgroups
* D-Star DCS/DPlus data with validated fallback behavior

This addresses searches such as:

```text
DVSwitch update failed
Pi-Star host files download error
YSFHosts.txt empty
P25Hosts.txt not updating
NXDNHosts.txt update failure
TGList_BM.txt invalid
TGList_TGIF.txt missing
DVSwitch database download returned HTML
```

### 2. ARM64 MMDVM_Bridge five-digit YSF and P25 fixes

The included binary is for **64-bit ARM/AArch64 only**.

Embedded corrected command format:

```text
REMOTE@%s:%d!Link%c%c%c %05d
```

For YSF reflector `44444`, this produces:

```text
LinkYSF 44444
```

Embedded corrected P25 remote-command format:

```text
REMOTE@%s:%d!TalkGroup %d
```

For P25 reflector `10201`, this produces:

```text
TalkGroup 10201
```

Runtime verification on node68425:

```text
Switched to reflector 10200 by remote command
Unlinked from reflector 10200 by remote command
Switched to reflector 10201 by remote command
```

Both the Analog Bridge `Tx TG/Ref` field and the P25 Net box updated immediately without PTT or a browser refresh.

> [!IMPORTANT]
> The earlier ARM64 checksum `9844cf4f...fc3ebe` applies to the YSF-only patched binary and must not be used for the new combined YSF+P25 binary.

Confirmed combined ARM64 binary checksum and size:

```text
SHA-256: 4da157f00c38a71bdcb6c192d3f86d8a352860fc1c9abb201c58fe24e554eb19
Size:    7084608 bytes
```

Tested with:

```text
MMDVM_Bridge version 20210520_V1.6.8 git #3cfcf23
Package: mmdvm-bridge 1.6.8-20241231-96 arm64
YSFGateway version 20211108 git #8946594
```

> [!CAUTION]
> Do not install this binary on AMD64/x86-64, ARMHF/32-bit ARM, or an unverified MMDVM_Bridge version.

### 2A. Optional ARMHF and AMD64 YSF five-digit compatibility binaries

Two additional architecture-specific binaries are included for users experiencing the same YSF reflector-number truncation problem on 32-bit ARM or 64-bit x86 systems:

| Repository file | Architecture | `dpkg --print-architecture` | Test status |
| --- | --- | --- | --- |
| `MMDVM_Bridge.armhf.ysf5-fixed` | ARMHF / 32-bit ARM | `armhf` | **Not live-tested** |
| `MMDVM_Bridge.amd64.ysf5-fixed` | AMD64 / x86-64 | `amd64` | **Not live-tested** |

> [!WARNING]
> These two optional binaries passed structural and checksum validation, but they have not yet been tested on live ARMHF or AMD64 DVSwitch nodes. The original five-digit formatting defect should be corrected, but users must treat these as experimental until successful reflector switching and audio are confirmed on each architecture.

Unlike the source-rebuilt ARM64 binary, these two binaries use a safe, same-size, one-byte compatibility patch:

```text
Original embedded format: REMOTE@%s:%d!Link%c%c%c%05d
Patched embedded format:  REMOTE@%s:%d!Link%c%c%c%06d
```

YSFGateway already discards the character in the position where the missing separator should have been. The additional leading zero occupies that position and leaves the complete five-digit reflector ID for YSFGateway to parse:

```text
Requested 44444 → transmitted LinkYSF044444 → parsed as 44444
Requested 53594 → transmitted LinkYSF053594 → parsed as 53594
Requested 02034 → transmitted LinkYSF002034 → parsed as 02034
```

Only one byte differs between each patched binary and its corresponding original. File size and ELF offsets remain unchanged.

Confirmed SHA-256 checksums:

```text
MMDVM_Bridge.armhf.ysf5-fixed
2846551df5a4e6c47626451e3c30a276baba6882412e9d8ee228eef00599aef7

MMDVM_Bridge.amd64.ysf5-fixed
f4a0e49fef216227449a31d2860bdf3234c68b5685ed51e4f4993eefe6659bbf
```

#### Install the optional ARMHF binary

This command checks for the Debian `armhf` architecture, verifies the checksum, creates a backup, stops the service, installs the file under its required runtime name `MMDVM_Bridge`, applies executable permissions, and restarts the service:

```bash
test "$(dpkg --print-architecture)" = "armhf" && echo "Architecture OK: armhf" || { echo "ERROR: This binary requires Debian ARMHF"; exit 1; }; echo '2846551df5a4e6c47626451e3c30a276baba6882412e9d8ee228eef00599aef7  MMDVM_Bridge.armhf.ysf5-fixed' | sha256sum -c - && sudo cp -a /opt/MMDVM_Bridge/MMDVM_Bridge "/opt/MMDVM_Bridge/MMDVM_Bridge.before-ysf5-armhf-fix-$(date +%Y%m%d-%H%M%S)" && sudo systemctl stop mmdvm_bridge.service && sudo install -m 755 MMDVM_Bridge.armhf.ysf5-fixed /opt/MMDVM_Bridge/MMDVM_Bridge && sudo systemctl start mmdvm_bridge.service && systemctl --no-pager --full status mmdvm_bridge.service
```

#### Install the optional AMD64 binary

This command checks for the Debian `amd64` architecture, verifies the checksum, creates a backup, stops the service, installs the file under its required runtime name `MMDVM_Bridge`, applies executable permissions, and restarts the service:

```bash
test "$(dpkg --print-architecture)" = "amd64" && echo "Architecture OK: amd64" || { echo "ERROR: This binary requires Debian AMD64"; exit 1; }; echo 'f4a0e49fef216227449a31d2860bdf3234c68b5685ed51e4f4993eefe6659bbf  MMDVM_Bridge.amd64.ysf5-fixed' | sha256sum -c - && sudo cp -a /opt/MMDVM_Bridge/MMDVM_Bridge "/opt/MMDVM_Bridge/MMDVM_Bridge.before-ysf5-amd64-fix-$(date +%Y%m%d-%H%M%S)" && sudo systemctl stop mmdvm_bridge.service && sudo install -m 755 MMDVM_Bridge.amd64.ysf5-fixed /opt/MMDVM_Bridge/MMDVM_Bridge && sudo systemctl start mmdvm_bridge.service && systemctl --no-pager --full status mmdvm_bridge.service
```

The downloaded architecture suffix is only used to identify the correct file. The installed executable **must** be named exactly:

```text
/opt/MMDVM_Bridge/MMDVM_Bridge
```

Linux filenames are case-sensitive. Do not leave the installed file named `MMDVM_Bridge.armhf.ysf5-fixed` or `MMDVM_Bridge.amd64.ysf5-fixed`. The `install -m 755` commands above perform the rename and set the required executable permissions automatically.

After installation, confirm the filename, ownership, permissions, architecture, version, and service state:

```bash
sudo ls -l /opt/MMDVM_Bridge/MMDVM_Bridge; file /opt/MMDVM_Bridge/MMDVM_Bridge; /opt/MMDVM_Bridge/MMDVM_Bridge -v; systemctl is-active mmdvm_bridge.service
```

Confirm that the compatibility format is present and the broken format is absent:

```bash
echo "=== FIXED FORMAT ==="; strings -a /opt/MMDVM_Bridge/MMDVM_Bridge | grep -F 'REMOTE@%s:%d!Link%c%c%c%06d' || echo "Fixed format not found"; echo "=== BROKEN FORMAT ==="; strings -a /opt/MMDVM_Bridge/MMDVM_Bridge | grep -F 'REMOTE@%s:%d!Link%c%c%c%05d' || echo "Broken format not present"
```

Then tune a known five-digit YSF reflector and verify that the YSFGateway log uses all five digits and that audio works. Do not publish either optional binary as confirmed working until it passes a live test on its intended architecture.

#### Roll back an optional binary

Locate the dated backup created by the installation command:

```bash
sudo ls -1t /opt/MMDVM_Bridge/MMDVM_Bridge.before-ysf5-*-fix-* | head
```

Replace `BACKUP_FILE` with the complete backup path shown above:

```bash
sudo systemctl stop mmdvm_bridge.service && sudo install -m 755 BACKUP_FILE /opt/MMDVM_Bridge/MMDVM_Bridge && sudo systemctl start mmdvm_bridge.service && systemctl --no-pager --full status mmdvm_bridge.service
```

#### Ask ChatGPT to review a test or troubleshoot a failure

Upload the original binary, the architecture-matched patched binary, and the relevant terminal output. Do not upload passwords, API keys, or unredacted private credentials. You can use this prompt:

```text
I am testing an experimental MMDVM_Bridge YSF five-digit reflector fix.

Hardware/architecture: [paste uname -m and dpkg --print-architecture]
Operating system: [paste cat /etc/os-release]
MMDVM_Bridge version: [paste /opt/MMDVM_Bridge/MMDVM_Bridge -v]
YSFGateway version: [paste /opt/YSFGateway/YSFGateway -v]
Patched file used: [ARMHF or AMD64 filename]
Reflector number tested: [five-digit number]

Please compare the attached original and patched binaries. Confirm their architectures, sizes, SHA-256 checksums, executable formats, and embedded YSF command strings. Verify that only the intended formatter changed from %05d to %06d. Then review the attached systemctl status and YSFGateway log output to determine whether all five digits were parsed and whether the reflector linked successfully. Do not suggest unrelated configuration changes or overwrite any files. Give all Linux terminal commands as single-line copy/paste commands and include a rollback command before recommending a replacement.
```

### 3. P25Gateway configuration cleanup

`P25Gateway.ini` was rewritten to match the configuration options supported by the installed P25Gateway binary. Obsolete or unsupported settings were removed while required operational settings were retained.

> [!WARNING]
> Gateway INI files contain node-specific values. Compare the supplied file with your existing configuration and preserve your callsign, IDs, addresses, ports, frequencies, location, and startup reflector.

### 4. YSFGateway configuration cleanup

`YSFGateway.ini` was rewritten for the installed binary:

```text
YSFGateway version 20211108 git #8946594
Package: ysfgateway 20240701-20 arm64
```

Unsupported and obsolete entries were removed, and supported missing settings were added.

The file includes node-specific identity and location data and must be reviewed before installation.

### 5. P25 dashboard link detection

`functions.php` adds recognition for:

```text
Switched to reflector #####
```

It also ensures `Switched` messages reach the P25 dashboard parser. This allows the stock DVSwitch Dashboard to show the actual linked P25 reflector instead of remaining `Unlinked`.

### 6. YSF and D-Star dashboard display repairs

`status.php` provides three visible corrections:

* Prevents the YSF Network box from displaying `null`.
* Uses case-insensitive YSF host-file matching.
* Changes `Tx TG` to the more accurate `Tx TG/Ref` label.
* Displays D-Star reflectors/modules such as `REF030 C` instead of `TG 0`.

---

## ✅ Compatibility

The complete repair set, including the combined ARM64 YSF and P25 binary fixes, was tested on:

```text
Raspberry Pi 5
ARM64 / AArch64
ASL3
Debian 13 Trixie host
DVSwitch packages from the Bookworm hamradio repository
Stock DVSwitch Dashboard
```

Individual PHP and shell-script changes may also be applicable to Debian 12 Bookworm and other architectures. The confirmed `MMDVM_Bridge` binary is strictly ARM64; separate experimental ARMHF and AMD64 compatibility binaries are included but remain live-test pending.

Before installing, record your versions:

```bash
/opt/MMDVM_Bridge/MMDVM_Bridge -v; /opt/YSFGateway/YSFGateway -v; /opt/P25Gateway/P25Gateway -v; dpkg -l | grep -Ei 'mmdvm-bridge|ysfgateway|p25gateway|dvswitch'
```

---

## 🛡️ Back Up Existing Files

Create a dated backup directory and copy all six active files before replacing anything:

```bash
backup_dir="/root/dvswitch-fix-backup-$(date +%Y%m%d-%H%M%S)"; sudo mkdir -p "$backup_dir/opt/MMDVM_Bridge" "$backup_dir/opt/YSFGateway" "$backup_dir/opt/P25Gateway" "$backup_dir/usr/share/dvswitch/include"; sudo cp -a /opt/MMDVM_Bridge/dvswitch.sh /opt/MMDVM_Bridge/MMDVM_Bridge "$backup_dir/opt/MMDVM_Bridge/"; sudo cp -a /opt/YSFGateway/YSFGateway.ini "$backup_dir/opt/YSFGateway/"; sudo cp -a /opt/P25Gateway/P25Gateway.ini "$backup_dir/opt/P25Gateway/"; sudo cp -a /usr/share/dvswitch/include/functions.php /usr/share/dvswitch/include/status.php "$backup_dir/usr/share/dvswitch/include/"; echo "Backup saved to $backup_dir"
```

---

## 📥 Installation

You can follow the following instructions, but if you know what you're doing, I suggest manually backing up each file and then replacing it with the patched file - Don't forget to make sure the replacement file has the same permissons as the original file. After replacing the files I suggest a reboot.

Clone the repository and enter its directory:

```bash
git clone https://github.com/ke2hni/DVSwitch-Fixes.git && cd DVSwitch-Fixes
```

> [!NOTE]
> Change the repository URL above if this project is published under a different repository name.

### Install `dvswitch.sh`

```bash
sudo install -m 755 dvswitch.sh /opt/MMDVM_Bridge/dvswitch.sh && bash -n /opt/MMDVM_Bridge/dvswitch.sh
```

### Install the patched ARM64 binary

Confirm that the system reports `aarch64`, verify the checksum, stop MMDVM_Bridge, install the binary, and restart the service:

```bash
test "$(uname -m)" = "aarch64" && echo "Architecture OK: aarch64" || { echo "ERROR: This binary requires aarch64"; exit 1; }; echo '4da157f00c38a71bdcb6c192d3f86d8a352860fc1c9abb201c58fe24e554eb19  MMDVM_Bridge' | sha256sum -c - && test "$(stat -c %s MMDVM_Bridge)" = "7084608" && echo "Size OK: 7084608 bytes" && sudo systemctl stop mmdvm_bridge.service && sudo install -m 755 MMDVM_Bridge /opt/MMDVM_Bridge/MMDVM_Bridge && sudo systemctl start mmdvm_bridge.service && systemctl --no-pager --full status mmdvm_bridge.service
```

### Install the dashboard PHP repairs

Check PHP syntax before replacement, install both files, and check the installed copies again:

```bash
php -l functions.php && php -l status.php && sudo install -m 644 functions.php /usr/share/dvswitch/include/functions.php && sudo install -m 644 status.php /usr/share/dvswitch/include/status.php && php -l /usr/share/dvswitch/include/functions.php && php -l /usr/share/dvswitch/include/status.php
```

### Review gateway INI files

Do **not** blindly overwrite your working gateway configurations. Compare them first:

```bash
diff -u /opt/P25Gateway/P25Gateway.ini P25Gateway.ini || true; diff -u /opt/YSFGateway/YSFGateway.ini YSFGateway.ini || true
```

After transferring your own node-specific values into the corrected files, install them and restart the gateways:

```bash
sudo install -m 644 P25Gateway.ini /opt/P25Gateway/P25Gateway.ini && sudo install -m 644 YSFGateway.ini /opt/YSFGateway/YSFGateway.ini && sudo systemctl restart p25gateway.service ysfgateway.service && systemctl --no-pager --full status p25gateway.service ysfgateway.service
```

---

## 🔊 RX Monitor Firewall Repair

The RX Monitor button uses:

```text
Browser WebSocket: TCP 8080
Analog_Bridge PCM output: UDP 2222
Web Proxy command: /opt/Web_Proxy/proxy.js 8080 2222
```

Check the active firewall zone before making changes:

```bash
sudo firewall-cmd --state; sudo firewall-cmd --get-active-zones
```

Replace `YOUR_ACTIVE_ZONE` with the zone reported above, then allow TCP 8080:

```bash
sudo firewall-cmd --permanent --zone=YOUR_ACTIVE_ZONE --add-port=8080/tcp && sudo firewall-cmd --reload && sudo firewall-cmd --zone=YOUR_ACTIVE_ZONE --query-port=8080/tcp
```

Confirm the Web Proxy listeners:

```bash
sudo ss -lntp | grep -E '(:8080[[:space:]])'; sudo ss -lunp | grep -E '(:2222[[:space:]])'; systemctl --no-pager --full status webproxy.service
```

Expected RX Monitor behavior:

| State | Button color |
| --- | --- |
| Idle/stopped | Dark blue |
| Hover | Lighter blue |
| Playing/connected | Green |
| Disconnected/retrying | Red |

> [!NOTE]
> The stock player changes the button to green before it proves that the WebSocket connection succeeded. A green button alone does not confirm connectivity. Verify an established connection with `ss` if audio is still missing.

---

## 🧪 Verification

### Verify the repaired YSF command

The corrected binary contains a space before `%05d`:

```bash
strings -a /opt/MMDVM_Bridge/MMDVM_Bridge | grep -F 'REMOTE@%s:%d!Link%c%c%c %05d'
```

### Verify the repaired P25 command

The corrected ARM64 binary contains a space before the P25 talkgroup formatter:

```bash
strings -a /opt/MMDVM_Bridge/MMDVM_Bridge | grep -F 'REMOTE@%s:%d!TalkGroup %d'
```

Confirm that the broken no-space format is absent:

```bash
strings -a /opt/MMDVM_Bridge/MMDVM_Bridge | grep -F 'REMOTE@%s:%d!TalkGroup%d' && echo 'ERROR: broken P25 format still present' || echo 'Broken P25 format not present'
```

### Verify PHP syntax and repair markers

```bash
php -l /usr/share/dvswitch/include/functions.php && php -l /usr/share/dvswitch/include/status.php && grep -nE 'Switched|Tx TG/Ref|strcasecmp|REF' /usr/share/dvswitch/include/functions.php /usr/share/dvswitch/include/status.php
```

### Verify services

```bash
systemctl is-active mmdvm_bridge.service ysfgateway.service p25gateway.service analog_bridge.service webproxy.service
```

### Verify five-digit YSF tuning

Tune a known five-digit reflector and inspect the current YSFGateway log:

```bash
sudo /opt/MMDVM_Bridge/dvswitch.sh tune 44444; sleep 3; sudo tail -n 40 "$(ls -1t /var/log/mmdvm/YSFGateway-*.log | head -n 1)"
```

The log should show a valid link attempt for all five digits, not a truncated four-digit number.

### Verify five-digit P25 remote tuning

Select P25 mode, tune two known five-digit reflectors without pressing PTT, and inspect the P25Gateway log:

```bash
sudo /opt/MMDVM_Bridge/dvswitch.sh mode p25; sleep 2; sudo /opt/MMDVM_Bridge/dvswitch.sh tune 10200; sleep 3; sudo /opt/MMDVM_Bridge/dvswitch.sh tune 10201; sleep 3; sudo tail -n 20 "$(ls -1t /var/log/mmdvm/P25Gateway-*.log | head -n 1)"
```

Expected messages include:

```text
Switched to reflector 10200 by remote command
Unlinked from reflector 10200 by remote command
Switched to reflector 10201 by remote command
```

The P25 Net box should update without PTT or a page refresh. Do not use the spoken prompt alone as the link test because the separate P25Gateway prompt-start issue described above is not yet fixed.

### Verify RX Monitor packet timing

During continuous received audio, approximately 50 packets per second is correct for the tested 8 kHz, 16-bit mono stream:

```bash
sudo timeout 5 strace -f -p "$(pgrep -f '/opt/Web_Proxy/proxy.js 8080 2222' | head -n 1)" -e trace=recvmsg 2>&1 | awk '/recvmsg\(.*\) = 320$/{n++} END{printf "320-byte PCM packets received in 5 seconds: %d\nApproximate packets per second: %.1f\n",n,n/5}'
```

Confirmed test result:

```text
320-byte PCM packets received in 5 seconds: 249
Approximate packets per second: 49.8
```

---

## 🚫 Files Inspected but Not Modified

The following were checked and found compatible with their installed binaries:

```text
/opt/NXDNGateway/NXDNGateway.ini
/etc/ircddbgateway
```

No NXDN or ircDDBGateway configuration replacement is included.

The RX Monitor investigation also confirmed that these did not require modification:

```text
/opt/Analog_Bridge/Analog_Bridge.ini
/opt/Web_Proxy/proxy.js
/usr/share/dvswitch/scripts/pcm-player.min.js
```

---

## 🧩 Separate Companion Projects

These projects were developed and tested alongside the core fixes but are intentionally not bundled into the six-file repair set:

* DVSwitch Dashboard responsive-layout improvements
* DVSwitch Dashboard Auto / Light / Dark Mode overlay

Keeping visual overlays separate prevents restore operations from accidentally overwriting functional repairs in `functions.php` or `status.php`.

---

## 🔁 Rollback

Restore the six files from the dated backup directory created earlier, then restart the affected services. Replace `BACKUP_DIRECTORY` with the actual backup path:

```bash
sudo cp -a BACKUP_DIRECTORY/opt/MMDVM_Bridge/dvswitch.sh BACKUP_DIRECTORY/opt/MMDVM_Bridge/MMDVM_Bridge /opt/MMDVM_Bridge/ && sudo cp -a BACKUP_DIRECTORY/opt/YSFGateway/YSFGateway.ini /opt/YSFGateway/ && sudo cp -a BACKUP_DIRECTORY/opt/P25Gateway/P25Gateway.ini /opt/P25Gateway/ && sudo cp -a BACKUP_DIRECTORY/usr/share/dvswitch/include/functions.php BACKUP_DIRECTORY/usr/share/dvswitch/include/status.php /usr/share/dvswitch/include/ && sudo systemctl restart mmdvm_bridge.service ysfgateway.service p25gateway.service
```

---

## ⚠️ Disclaimer

These repairs are community-tested modifications and are not an official DVSwitch release.

* Back up every original file.
* Confirm package and binary versions before replacement.
* Preserve your own callsign, IDs, ports, frequencies, location, and network settings.
* Test one change at a time.
* Keep console or SSH access available during testing.
* Use at your own risk on production radio systems.

---

## 📜 License

Use, study, and adapt these fixes for amateur-radio and educational purposes. Preserve upstream copyright and license notices contained in original DVSwitch source files and binaries.

---

## 🙏 Credits

DVSwitch and its component software remain the work of their respective developers and contributors. This repository documents and packages community troubleshooting repairs tested by **KE2HNI** on **node68425**.

---

<p align="center">
  🛠️ Built from real-world DVSwitch troubleshooting, verified one repair at a time.
</p>

