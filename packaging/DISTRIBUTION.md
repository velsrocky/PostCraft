# AppImageHub / AUR packaging inputs for PostCraft.

## GitHub Releases (primary)

CI (`.github/workflows/release-linux.yml`) builds `PostCraft-<version>-x86_64.AppImage`,
writes `SHA256SUMS`, and publishes a GitHub Release tagged `v<version>`.

## AUR

1. After each release, update `pkgver` in `packaging/aur/PKGBUILD`.
2. Compute sha256 for the AppImage, desktop file, appdata, and SVG:
   `sha256sum PostCraft-1.0.0-x86_64.AppImage packaging/linux/*`
3. Copy this directory to your AUR package checkout, replace SKIP sums, and push
   to `https://aur.archlinux.org/postcraft-appimage.git`.
4. Optional: enable an AUR update bot for automated bumps.

Runtime dependency: `ffmpeg` (PostCraft does not bundle FFmpeg).

## AppImageHub

Repo is public. Open a PR at https://github.com/AppImage/appimage.github.io
with:

- Name: PostCraft
- Description: Local-first screenshot annotation and media studio
- Screenshot: (add a product screenshot)
- Categories: Graphics, Photography
- Download: https://github.com/velsrocky/PostCraft/releases/download/v1.0.0/PostCraft-1.0.0-x86_64.AppImage
- Homepage: https://github.com/velsrocky/PostCraft
- License: MIT

Icon: `packaging/linux/com.velstech.postcraft.svg`

SHA-256 (v1.0.0): `336f54af58fe5f09edbf87e1c3b1446689e3c423c159225a4c48ef1feef3f994`
