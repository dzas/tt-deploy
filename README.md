# TrustTunnel Deploy Monorepo

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

## GitHub Actions

- `.github/workflows/admin-bot-publish.yml`
- `.github/workflows/installer-release.yml`

## Notes

- `server/` is kept as local reference mirror and is not part of automated CI
  delivery in this model.
- Endpoint image build/push procedure is documented in
  `docs/ENDPOINT_IMAGE_MANUAL.md`.
