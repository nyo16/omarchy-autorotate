# Auto-rotate for Omarchy

Rotates the built-in display from the accelerometer on 2-in-1 laptops, the way Windows does: when you fold the screen back into tablet or tent mode, or all the time if you prefer. A bar icon works as a rotation lock.

## Install

```bash
omarchy plugin add https://github.com/nmaroulis/omarchy-autorotate.git
~/.config/omarchy/plugins/io.github.nmaroulis.autorotate/setup
```

`setup` does what `omarchy plugin add` can't:

1. Installs `iio-sensor-proxy`, which reads the accelerometer.
2. Installs the laptop maker's sensor hub firmware if there's no accelerometer (see below). Reboot afterwards.
3. Writes `~/.config/hypr/autorotate.lua`, which binds the laptop's tablet-mode switch to the plugin, and adds a `require` line for it to `hyprland.lua`.
4. Enables the plugin.

`setup --remove` undoes steps 2 and 3. Then run `omarchy plugin remove io.github.nmaroulis.autorotate`.

## Modes

| Mode | Rotates |
|---|---|
| `tablet` (default) | only while folded into tablet/tent mode. Folding back to a laptop returns the screen to normal |
| `always` | whenever the device turns |
| `off` | never |

Set the mode with `omarchy-shell autorotate mode tablet|always|off`, or right-click the bar icon to cycle through them. Left-click the icon to lock or unlock rotation. The lock only applies while rotation is active: folding back into a laptop always returns the screen to normal.

The settings are stored in `~/.config/omarchy/autorotate.json`:

```json
{ "mode": "tablet", "locked": false, "monitor": "eDP-1" }
```

`monitor` is the output to rotate. The file reloads on save.

IPC (`omarchy-shell autorotate <method>`): `status`, `mode <name>`, `cycle`, `lock`, `unlock`, `toggleLock`, `tablet on|off`.

## Sensor hub firmware (Intel Lunar Lake and newer)

On Core Ultra 200V (Lunar Lake) and later, the accelerometer is wired to Intel's Integrated Sensor Hub (ISH), and the OS has to hand the ISH its firmware at every boot. OEM boards only accept the image signed for them, and `linux-firmware` ships Intel's generic image plus a few vendor ones. That leaves most of these 2-in-1s with no sensors on Linux. The kernel log shows `ISH loader: cmd 2 failed 10`.

`bin/omarchy-autorotate-firmware` fixes this using the image Windows already loads:

```bash
omarchy-autorotate-firmware status      # what the kernel looks for, what it loaded, accelerometer present?
omarchy-autorotate-firmware install     # find the OEM image on the Windows partition, package it, install it
omarchy-autorotate-firmware install --from ishC_….bin   # or use an image you extracted yourself
omarchy-autorotate-firmware remove
```

It searches the Windows driver store for `FwImage/<platform>/ishC_*.bin`, the OEM image that the vendor's ISH extension driver loads in place of Intel's generic one. If the Windows partition isn't mounted, it mounts it read-only. It then builds a local pacman package, `omarchy-autorotate-ish-firmware`, which installs the image as `/usr/lib/firmware/updates/intel/ish/ish_<gen>_<crc32(sys_vendor)>_<crc32(product_name)>.bin`. That is the name the kernel's ISH loader looks for before falling back to the generic image. Nothing is flashed: the ISH loads the image into memory at each boot. A rejected image needs a reboot before another one can be tried.

The firmware isn't redistributable, so it never ships in this repository.

Tested on: HP OmniBook Ultra Flip 14-fh0xxx (Lunar Lake; LIS2DW12 and LSM6DSOX sensors).

## Development

```bash
node tests/model.test.js
omarchy plugin validate .
```
