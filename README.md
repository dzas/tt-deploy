# TrustTunnel Deploy Monorepo

Language: [EN](README.md) | [RU](README_RU.md)

Quick Links:
- Deploy from release (EN): `docs/DEPLOY_FROM_RELEASE.md`
- Deploy from release (RU): `docs/DEPLOY_FROM_RELEASE_RU.md`
- Installer guide (EN): `installer/INSTALLER_GUIDE.md`
- Installer guide (RU): `installer/INSTALLER_GUIDE_RU.md`
- Endpoint image manual (EN): `docs/ENDPOINT_IMAGE_MANUAL.md`
- Endpoint image manual (RU): `docs/ENDPOINT_IMAGE_MANUAL_RU.md`
- Release checklist (EN): `docs/RELEASE_CHECKLIST.md`
- Release checklist (RU): `docs/RELEASE_CHECKLIST_RU.md`

This repository contains deployment automation and management tooling for a
self-hosted TrustTunnel setup.

## Components

- `installer/` - bash installer with `plan/apply/resume/verify` modes.
- `admin_bot/` - Telegram admin bot image source and deployment helper.
- `release/` - release manifest templates for installer bundles.
- `docs/` - release checklist and VPS deployment flow.

## Delivery Model

- TrustTunnel endpoint image: built locally when needed and pushed to GHCR.
- Admin bot image: published by GitHub Actions.
- Installer: released as versioned tarball assets in GitHub Releases.

## Notes

- `server/` is kept as local reference mirror and is not part of automated CI
  delivery in this model.
- Endpoint image build/push procedure is documented in
  `docs/ENDPOINT_IMAGE_MANUAL.md`.

## Deploy On VPS

Use release assets for installation on a fresh VPS.

Quick flow:

1. Download installer assets from GitHub Release (`installer-<version>.tar.gz`, `manifest-<version>.json`, `SHA256SUMS`).
2. Verify checksums.
3. Edit `installer/installer.env` and `installer/secrets.env`.
4. Run:
   - `./tt-installer.sh plan --config ./installer.env --secrets ./secrets.env --interactive`
   - `./tt-installer.sh apply --config ./installer.env --secrets ./secrets.env`

Detailed guide: `docs/DEPLOY_FROM_RELEASE.md`.
