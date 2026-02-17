# Android Image Kitchen (Container-First on macOS)

This repository packages Android Image Kitchen (AIK) for reliable use on macOS, especially Apple Silicon, by defaulting to a Linux container runtime.

## Why container-first

On macOS, Android boot tooling names and flags are not always compatible (`unpackbootimg` vs `unpack_bootimg`, missing host binaries, etc.).

This project keeps host setup minimal:
- Keep only Docker/OrbStack on host.
- Run AIK tooling inside a reproducible Linux image.
- Avoid polluting host PATH with Android-specific tools.

## Requirements

- macOS with OrbStack or Docker Desktop
- `docker` CLI available in PATH

## Repository layout

- `unpackimg.sh` / `repackimg.sh` / `cleanup.sh`: main AIK scripts
- `lib/runtime.sh`: runtime detection, container forwarding, tool adapters
- `Dockerfile`: runtime image definition (`aik-runtime:local`)
- `tests/smoke.sh`: publish smoke regression test
- `testdata/images/twrp-3.0.2-0-sirius.img`: sample image for regression tests

## Quick start

Build runtime image:

```bash
docker build -t aik-runtime:local .
```

Unpack:

```bash
./unpackimg.sh testdata/images/twrp-3.0.2-0-sirius.img
```

Repack:

```bash
./repackimg.sh
```

Cleanup:

```bash
./cleanup.sh
```

## Runtime options

Supported by `unpackimg.sh`, `repackimg.sh`, and `cleanup.sh`:

- `--runtime native|auto|container`
- `--container-image <image>`
- `--strict-native`
- `--doctor`
- `--native` (shortcut for `--runtime native`)

Environment variables:

- `AIK_RUNTIME`
- `AIK_CONTAINER_IMAGE`
- `AIK_STRICT_NATIVE`

Default behavior on macOS is container runtime.

## Testing

Run smoke tests:

```bash
bash tests/smoke.sh
```

The test suite validates:
- doctor check
- unpack sample image
- repack
- roundtrip re-unpack
- final cleanup

## Troubleshooting

### `unpack_bootimg: ... --boot_img required`

Cause: backend tool expects `unpack_bootimg --boot_img`, while legacy AIK flow uses `unpackbootimg -i`.

Status in this repo: fixed via runtime adapter in `lib/runtime.sh`.

### Docker permission or daemon errors

Verify OrbStack/Docker is running and the active Docker context is valid:

```bash
docker context ls
docker ps
```

### Missing signing assets (`boot_signer.jar`, `bin/avb/*`, `bin/chromeos/*`)

Some signature flows require extra assets not present in this trimmed repo. Repack will fail with explicit error messages if those assets are needed.

## Notes for publishing

Before pushing:

```bash
bash -n unpackimg.sh repackimg.sh cleanup.sh lib/runtime.sh tests/smoke.sh
bash tests/smoke.sh
```
