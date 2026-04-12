# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added

- GitHub Actions workflow (`.github/workflows/ghcr.yml`) to build and push the server image to `ghcr.io/<owner>/rx-vpn` (`latest` and commit SHA tags).
- Root `VERSION` file; FastAPI reads the app version from it; the Dockerfile copies `VERSION` into the image.
- Optional Git hooks under `scripts/git-hooks/` plus `scripts/setup-git-hooks.sh` — enables automatic patch bumps in `VERSION` on each commit (set `SKIP_VERSION_BUMP=1` to skip).

### Changed

- Debian package sources for the Ubuntu client live under `client/ubuntu24/`; CI builds the `.deb` from that path.
- `.gitignore` extended for Debian build artifacts and client build outputs.

### Notes

- For anonymous `docker pull`, set the GHCR package visibility to **Public** in the repository’s Packages settings.
