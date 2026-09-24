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
4. Optional: enable D-Arsecondary bot for automated updates.

Runtime dependency: `ffmpeg` (PostCraft does not bundle FFmpeg).

## AppImageHub

After a public release, open a PR at https://github.com/AppImage/appimage.github.io
with:

- Name: PostCraft
- Description: Local-first screenshot annotation and media studio
- Screenshot: (add a product screenshot)
- Categories: Graphics, Photography
- Download: the GitHub Release AppImage URL
- Homepage: https://github.com/velsrocky/PostCraft
- License: MIT

Icon: `packaging/linux/com.velstech.postcraft.svg`
