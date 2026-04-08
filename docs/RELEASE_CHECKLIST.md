# Release Checklist

## 1) Endpoint Image (manual, local build)

- Build TrustTunnel endpoint image locally from your selected TrustTunnel source ref.
- Push image to GHCR: `ghcr.io/<owner>/tt-endpoint:<version>`.
- Record pushed digest for release notes/manifest.

## 2) Admin Bot Image (GitHub Actions)

- Ensure changes in `admin_bot/` are merged.
- Confirm workflow `.github/workflows/admin-bot-publish.yml` is green.
- Verify image in GHCR: `ghcr.io/<owner>/tt_admin_bot:<version or sha>`.

## 3) Installer Bundle (GitHub Release)

- Create git tag: `vX.Y.Z`.
- Verify workflow `.github/workflows/installer-release.yml` completed.
- Confirm release assets exist:
  - `installer-vX.Y.Z.tar.gz`
  - `manifest-vX.Y.Z.json`
  - `SHA256SUMS`

## 4) Manifest Review

- Open `manifest-vX.Y.Z.json` in release assets.
- Ensure image refs point to intended endpoint and bot versions.
- Prefer digest-based refs (`@sha256:...`) for production deployments.

## 5) Smoke Test

- On a fresh VPS run installer in `plan` mode.
- Run `apply` with final image refs.
- Validate endpoint and bot health.
