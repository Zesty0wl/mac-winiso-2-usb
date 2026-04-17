# Windows Bootable USB Creator for macOS

Create bootable Windows USB drives on macOS -- no Terminal, no Homebrew, no fuss.

## WINISO2USB (GUI App)

A native macOS app that wraps the entire process in a guided wizard. All dependencies (including wimlib for splitting oversized install.wim files) are bundled inside the app -- nothing to install.

### Requirements

- macOS 14.0 (Sonoma) or later
- 8 GB+ USB drive (16 GB recommended)
- A Windows ISO file (Windows 10 or 11)

### Wizard Steps

1. **Select ISO** -- Drag and drop a Windows ISO file (or use the file picker). The app validates the ISO and extracts edition/version metadata.
2. **Select USB** -- Pick a connected removable USB drive. Internal and boot disks are filtered out for safety.
3. **Review** -- Confirm your selections before the destructive operation begins.
4. **Creating** -- The app erases the drive (GPT + FAT32), copies files, and splits install.wim if needed. Real-time progress, speed, and ETA are shown.
5. **Complete** -- Eject and go. The USB is ready to boot on any UEFI system.

### Building from Source

Open `WINISO2USB/WINISO2USB.xcodeproj` in Xcode 16+ and build. The project uses Swift 6 with strict concurrency. The bundled `wimlib-imagex` binary and `libwim.15.dylib` are copied into the app bundle by a build phase script that also fixes dylib load paths and re-signs both with hardened runtime.

### Project Structure

```
WINISO2USB/
  WINISO2USB.xcodeproj/     Xcode project
  WINISO2USB/
    WINISO2USBApp.swift      App entry point
    Models/               WizardState, USBDrive, ISOMetadata
    Views/                SwiftUI wizard steps
    Services/             DiskService, ISOService, USBCreationService, ProcessRunner
    Resources/bin/        Bundled wimlib-imagex + libwim.15.dylib
    Assets.xcassets/      App icon
```

---

## Command-Line Script

For those who prefer the terminal, the original shell script is still available.

### Prerequisites

Built-in macOS tools (`diskutil`, `hdiutil`, `rsync`) cover most cases. **wimlib** is only needed if your ISO contains an `install.wim` larger than 4 GB:

```bash
brew install wimlib
```

### Usage

```bash
./createWin11BootUsb.zsh -i /path/to/Windows.iso -d diskX -n WIN11
```

| Parameter | Required | Description | Default |
|-----------|----------|-------------|---------|
| `-i` | Yes | Path to Windows ISO file | -- |
| `-d` | No | Target disk identifier (e.g. `disk2`) | Interactive prompt |
| `-n` | No | USB volume name | `WINDOWSUSB` |
| `-s` | No | Split size in MB for install.wim | `3800` |
| `-h` | No | Show help message | -- |

If `-d` is omitted, the script lists available disks and prompts for selection.

---

## How It Works

Both the GUI app and the script follow the same pipeline:

1. **Validate** -- Check the ISO signature and confirm the target is a removable USB drive.
2. **Erase** -- Unmount, then format as GPT + FAT32 for UEFI boot compatibility.
3. **Mount ISO** -- Attach the ISO (detects already-mounted images).
4. **Copy files** -- rsync everything to the USB. If `install.wim` exceeds 4 GB, it is excluded and then split into `.swm` chunks using wimlib.
5. **Sync and eject** -- Flush writes, detach the ISO, eject the USB.

### Why GPT + FAT32?

- **GPT** is required for UEFI boot on modern systems.
- **FAT32** is the only filesystem universally supported for UEFI boot.
- FAT32 has a 4 GB file size limit, which is why large `install.wim` files must be split. Windows Setup automatically recognises split `.swm` archives.

## Safety

- Internal and boot disks are rejected.
- The script requires typing "ERASE" to confirm; the app shows a review step.
- Hardened runtime is enabled on the app and all bundled binaries.

## Compatibility

- **Windows versions:** 10, 11, Server 2016/2019/2022
- **macOS:** 14.0+ for the app; 10.13+ for the script
- **Architecture:** Intel and Apple Silicon

### Target PC Requirements
- UEFI firmware (most PCs from 2012+)
- USB boot support
- UEFI mode enabled (not Legacy/CSM)

## License

WINISO2USB (the Swift application and the `createWin11BootUsb.zsh` script) is
released under the [MIT License](LICENSE).

The macOS app bundle ships `wimlib-imagex` (GPL-3.0-or-later) and
`libwim.15.dylib` (LGPL-3.0-or-later) as unmodified upstream binaries, invoked
as a subprocess. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for full
attribution and the written offer for corresponding source code.

## Credits

- Uses [`wimlib`](https://wimlib.net/) for WIM file manipulation.
- Inspired by various Windows USB creation tools for macOS.

## Contributing

Feel free to submit issues or pull requests for improvements!

---

**Note**: This script is for creating Windows installation media only. You still need a valid Windows license to install and activate Windows.
