# Third-Party Notices

WINISO2USB is licensed under the MIT License (see `LICENSE`). The application
bundle additionally contains unmodified third-party binaries that are
distributed under their own licenses, listed below.

---

## wimlib (`wimlib-imagex`, `libwim.15.dylib`)

- **Project:** wimlib — a library and command-line tool for creating, modifying, extracting and mounting WIM (Windows Imaging) files.
- **Home page:** https://wimlib.net/
- **Upstream source:** https://wimlib.net/downloads/
- **License:**
  - `wimlib-imagex` (command-line tool): GNU General Public License, version 3 or later (GPL-3.0-or-later).
  - `libwim.15.dylib` (shared library): GNU Lesser General Public License, version 3 or later (LGPL-3.0-or-later).
- **Usage in this project:** `wimlib-imagex` is invoked as a separate subprocess from the main application to split `install.wim` files larger than 4 GB into `.swm` chunks. It is not statically or dynamically linked into WINISO2USB's own Swift code; it is shipped in the app's `Resources/bin/` directory and launched via `Process`. The accompanying `libwim.15.dylib` is loaded only by `wimlib-imagex` itself.
- **Modifications:** None. The binaries are built from unmodified upstream sources.

### Written offer for source code

In accordance with sections 6 and 3 of the GPL-3.0 / LGPL-3.0 respectively,
the complete corresponding source code for the version of wimlib bundled
with this application is available:

1. **Online:** at https://wimlib.net/downloads/ (upstream tarballs).
2. **On request:** by opening an issue on this project's GitHub repository, or by emailing the maintainer listed in the repository metadata. The maintainer will provide, for a period of at least three years from the date of distribution, a copy of the corresponding source code of the exact wimlib version bundled with the release you received, at no charge beyond the reasonable cost of physically performing source distribution.

The full text of the GPL-3.0 and LGPL-3.0 licenses can be read at:

- https://www.gnu.org/licenses/gpl-3.0.txt
- https://www.gnu.org/licenses/lgpl-3.0.txt

---

## Windows, Windows 10, Windows 11

Microsoft, Windows, Windows 10, and Windows 11 are trademarks of Microsoft
Corporation. This project is not affiliated with, endorsed by, or sponsored
by Microsoft. Users are responsible for obtaining a valid Windows license
and a legitimate Windows installation ISO from Microsoft.
