#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE:-$0}")/.." && pwd -P)"
cd "$ROOT_DIR"

CONTAINER_IMAGE="${AIK_CONTAINER_IMAGE:-aik-runtime:local}"
SAMPLE_IMAGE="testdata/images/twrp-3.0.2-0-sirius.img"

on_error() {
  local exit_code="$?"
  echo ""
  echo "[FAIL] tests/smoke.sh failed at line ${BASH_LINENO[0]}"
  echo "Hint: verify Docker/OrbStack is running and image '$CONTAINER_IMAGE' is buildable."
  exit "$exit_code"
}
trap on_error ERR

log_step() {
  echo ""
  echo "==> $1"
}

assert_exists() {
  local path="$1"
  if [ ! -e "$path" ]; then
    echo "Expected path missing: $path"
    return 1
  fi
}

assert_glob() {
  local pattern="$1"
  if ! compgen -G "$pattern" >/dev/null; then
    echo "Expected files matching pattern: $pattern"
    return 1
  fi
}

if ! command -v docker >/dev/null 2>&1; then
  echo "docker CLI is required"
  exit 1
fi

if [ ! -f "$SAMPLE_IMAGE" ]; then
  echo "Sample image not found: $SAMPLE_IMAGE"
  exit 1
fi

if ! docker image inspect "$CONTAINER_IMAGE" >/dev/null 2>&1; then
  log_step "Building runtime image ($CONTAINER_IMAGE)"
  docker build -t "$CONTAINER_IMAGE" .
fi

log_step "Initial cleanup"
./cleanup.sh --quiet || true

log_step "Doctor check"
./unpackimg.sh --doctor

log_step "Unpack sample image"
./unpackimg.sh "$SAMPLE_IMAGE"
assert_exists split_img
assert_exists ramdisk
assert_glob "split_img/*-imgtype"
assert_glob "split_img/*-*ramdiskcomp"

log_step "Repack image"
./repackimg.sh

NEW_IMAGE=""
if [ -f image-new.img ]; then
  NEW_IMAGE="image-new.img"
elif [ -f unsigned-new.img ]; then
  NEW_IMAGE="unsigned-new.img"
else
  echo "Expected repack output missing: image-new.img or unsigned-new.img"
  exit 1
fi

log_step "Roundtrip re-unpack"
cp -f "$NEW_IMAGE" roundtrip-test.img
./cleanup.sh --quiet
./unpackimg.sh roundtrip-test.img
assert_exists split_img
assert_exists ramdisk
assert_glob "split_img/*-imgtype"
assert_glob "split_img/*-*ramdiskcomp"

log_step "Final cleanup"
./cleanup.sh --quiet
rm -f roundtrip-test.img
if [ -d split_img ] || [ -d ramdisk ]; then
  echo "cleanup.sh left working directories behind"
  exit 1
fi

echo ""
echo "[PASS] Smoke tests completed"
