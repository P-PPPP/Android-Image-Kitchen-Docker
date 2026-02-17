#!/bin/bash

# Shared runtime helpers for AIK scripts.

AIK_DEFAULT_CONTAINER_IMAGE="aik-runtime:local"

_aik_script_dir() {
  local src="$1"
  cd "$(dirname "$src")" && pwd -P
}

aik_readlink_f() {
  local path="$1"
  if command -v readlink >/dev/null 2>&1; then
    local out
    out="$(readlink -f "$path" 2>/dev/null)"
    if [ -n "$out" ]; then
      printf '%s\n' "$out"
      return 0
    fi
  fi
  perl -MCwd -e 'print Cwd::abs_path shift' "$path"
}

aik_detect_platform() {
  case "$(uname -s)" in
    Darwin|Macintosh) AIK_OS="macos" ;;
    *) AIK_OS="linux" ;;
  esac

  case "$(uname -m)" in
    arm64|aarch64) AIK_ARCH="arm64" ;;
    x86_64|amd64) AIK_ARCH="x86_64" ;;
    *) AIK_ARCH="$(uname -m)" ;;
  esac
}

aik_parse_common_args() {
  local args=()
  AIK_DOCTOR=0
  AIK_FORCE_NATIVE=0

  while [ "$1" ]; do
    case "$1" in
      --doctor)
        AIK_DOCTOR=1
        ;;
      --native)
        AIK_RUNTIME="native"
        AIK_FORCE_NATIVE=1
        ;;
      --strict-native)
        AIK_STRICT_NATIVE=1
        ;;
      --runtime)
        shift
        [ "$1" ] && AIK_RUNTIME="$1"
        ;;
      --runtime=*)
        AIK_RUNTIME="${1#*=}"
        ;;
      --container-image)
        shift
        [ "$1" ] && AIK_CONTAINER_IMAGE="$1"
        ;;
      --container-image=*)
        AIK_CONTAINER_IMAGE="${1#*=}"
        ;;
      *)
        args+=("$1")
        ;;
    esac
    shift
  done

  AIK_ARGS=("${args[@]}")
}

aik_has_docker() {
  command -v docker >/dev/null 2>&1
}

aik_container_image_ready() {
  docker image inspect "$AIK_CONTAINER_IMAGE" >/dev/null 2>&1
}

aik_ensure_container_image() {
  if aik_container_image_ready; then
    return 0
  fi

  if [ ! -f "$AIK_ROOT/Dockerfile" ]; then
    echo "Missing Docker image and Dockerfile: $AIK_CONTAINER_IMAGE" >&2
    return 1
  fi

  echo "Building container image: $AIK_CONTAINER_IMAGE"
  docker build -t "$AIK_CONTAINER_IMAGE" "$AIK_ROOT"
}

aik_exec_in_container() {
  local script_abs="$1"
  shift

  local uidgid
  uidgid="$(id -u):$(id -g)"

  docker run --rm \
    -e AIK_IN_CONTAINER=1 \
    -e AIK_RUNTIME=native \
    -e AIK_STRICT_NATIVE=1 \
    -e TERM="$TERM" \
    -u "$uidgid" \
    -v "$AIK_ROOT:$AIK_ROOT" \
    -v "$PWD:$PWD" \
    -w "$PWD" \
    "$AIK_CONTAINER_IMAGE" \
    bash "$script_abs" "$@"
}

aik_resolve_tool() {
  local tool="$1"
  local candidate="$AIK_ROOT/bin/$AIK_OS/$AIK_ARCH/$tool"
  local alias

  if [ -x "$candidate" ]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  if command -v "$tool" >/dev/null 2>&1; then
    command -v "$tool"
    return 0
  fi

  case "$tool" in
    unpackbootimg) alias="unpack_bootimg" ;;
  esac
  if [ -n "$alias" ] && command -v "$alias" >/dev/null 2>&1; then
    command -v "$alias"
    return 0
  fi

  return 1
}

aik_tool() {
  aik_resolve_tool "$1"
}

aik_exec() {
  local tool="$1"
  shift

  local resolved
  resolved="$(aik_resolve_tool "$tool")" || {
    echo "Missing required tool: $tool" >&2
    return 127
  }

  if [ "$tool" = "mkbootimg" ]; then
    PYTHONPATH="$AIK_ROOT/lib/python:${PYTHONPATH:-}" "$resolved" "$@"
    return $?
  fi

  "$resolved" "$@"
}

aik_exec_unpackbootimg() {
  local resolved
  resolved="$(aik_resolve_tool unpackbootimg)" || {
    echo "Missing required tool: unpackbootimg" >&2
    return 127
  }

  # Ubuntu's mkbootimg package exposes unpack_bootimg with a different CLI.
  if [ "$(basename "$resolved")" = "unpack_bootimg" ]; then
    local boot_img=""
    local out_dir="."
    local passthrough=()
    local arg
    local base_name
    local comp
    local mk_args
    local -a parsed_args=()
    local key
    local val

    while [ "$1" ]; do
      arg="$1"
      case "$arg" in
        -i|--input|--boot_img)
          shift
          boot_img="$1"
          ;;
        -o|--out)
          shift
          out_dir="$1"
          ;;
        *)
          passthrough+=("$arg")
          ;;
      esac
      shift
    done

    if [ -z "$boot_img" ]; then
      echo "unpackbootimg adapter requires input image (-i/--boot_img)." >&2
      return 2
    fi

    "$resolved" --boot_img "$boot_img" --out "$out_dir" "${passthrough[@]}"
    [ ! $? -eq 0 ] && return 1

    base_name="$(basename "$boot_img")"
    for comp in kernel ramdisk second dtb recovery_dtbo vendor_ramdisk; do
      if [ -f "$out_dir/$comp" ]; then
        mv -f "$out_dir/$comp" "$out_dir/$base_name-$comp"
      fi
    done

    mk_args="$("$resolved" --boot_img "$boot_img" --format=mkbootimg 2>/dev/null)" || return 1
    eval "parsed_args=($mk_args)"

    while [ "${#parsed_args[@]}" -gt 0 ]; do
      key="${parsed_args[0]}"
      parsed_args=("${parsed_args[@]:1}")
      case "$key" in
        --cmdline|--vendor_cmdline) [ "${#parsed_args[@]}" -gt 0 ] && { val="${parsed_args[0]}"; parsed_args=("${parsed_args[@]:1}"); printf '%s\n' "$val" > "$out_dir/$base_name-cmdline"; } ;;
        --board) [ "${#parsed_args[@]}" -gt 0 ] && { val="${parsed_args[0]}"; parsed_args=("${parsed_args[@]:1}"); printf '%s\n' "$val" > "$out_dir/$base_name-board"; } ;;
        --base) [ "${#parsed_args[@]}" -gt 0 ] && { val="${parsed_args[0]}"; parsed_args=("${parsed_args[@]:1}"); printf '%s\n' "$val" > "$out_dir/$base_name-base"; } ;;
        --pagesize) [ "${#parsed_args[@]}" -gt 0 ] && { val="${parsed_args[0]}"; parsed_args=("${parsed_args[@]:1}"); printf '%s\n' "$val" > "$out_dir/$base_name-pagesize"; } ;;
        --kernel_offset) [ "${#parsed_args[@]}" -gt 0 ] && { val="${parsed_args[0]}"; parsed_args=("${parsed_args[@]:1}"); printf '%s\n' "$val" > "$out_dir/$base_name-kernel_offset"; } ;;
        --ramdisk_offset) [ "${#parsed_args[@]}" -gt 0 ] && { val="${parsed_args[0]}"; parsed_args=("${parsed_args[@]:1}"); printf '%s\n' "$val" > "$out_dir/$base_name-ramdisk_offset"; } ;;
        --second_offset) [ "${#parsed_args[@]}" -gt 0 ] && { val="${parsed_args[0]}"; parsed_args=("${parsed_args[@]:1}"); printf '%s\n' "$val" > "$out_dir/$base_name-second_offset"; } ;;
        --tags_offset) [ "${#parsed_args[@]}" -gt 0 ] && { val="${parsed_args[0]}"; parsed_args=("${parsed_args[@]:1}"); printf '%s\n' "$val" > "$out_dir/$base_name-tags_offset"; } ;;
        --dtb_offset) [ "${#parsed_args[@]}" -gt 0 ] && { val="${parsed_args[0]}"; parsed_args=("${parsed_args[@]:1}"); printf '%s\n' "$val" > "$out_dir/$base_name-dtb_offset"; } ;;
        --os_version) [ "${#parsed_args[@]}" -gt 0 ] && { val="${parsed_args[0]}"; parsed_args=("${parsed_args[@]:1}"); printf '%s\n' "$val" > "$out_dir/$base_name-os_version"; } ;;
        --os_patch_level) [ "${#parsed_args[@]}" -gt 0 ] && { val="${parsed_args[0]}"; parsed_args=("${parsed_args[@]:1}"); printf '%s\n' "$val" > "$out_dir/$base_name-os_patch_level"; } ;;
        --header_version) [ "${#parsed_args[@]}" -gt 0 ] && { val="${parsed_args[0]}"; parsed_args=("${parsed_args[@]:1}"); printf '%s\n' "$val" > "$out_dir/$base_name-header_version"; } ;;
        --hashtype) [ "${#parsed_args[@]}" -gt 0 ] && { val="${parsed_args[0]}"; parsed_args=("${parsed_args[@]:1}"); printf '%s\n' "$val" > "$out_dir/$base_name-hashtype"; } ;;
        *)
          case "$key" in
            --*)
              [ "${#parsed_args[@]}" -gt 0 ] && parsed_args=("${parsed_args[@]:1}")
              ;;
          esac
          ;;
      esac
    done

    return $?
  fi

  "$resolved" "$@"
}

aik_fix_permissions() {
  local aik="$1"
  local bin="$2"

  chmod -R 755 "$bin" "$aik"/*.sh 2>/dev/null || true

  [ -f "$bin/magic" ] && chmod 644 "$bin/magic"
  [ -f "$bin/androidbootimg.magic" ] && chmod 644 "$bin/androidbootimg.magic"
  [ -f "$bin/boot_signer.jar" ] && chmod 644 "$bin/boot_signer.jar"

  if [ -d "$bin/avb" ]; then
    chmod 644 "$bin/avb"/* 2>/dev/null || true
  fi

  if [ -d "$bin/chromeos" ]; then
    chmod 644 "$bin/chromeos"/* 2>/dev/null || true
  fi
}

aik_check_required_tools() {
  local missing=0
  local tool

  for tool in "$@"; do
    if ! aik_resolve_tool "$tool" >/dev/null 2>&1; then
      echo "MISSING: $tool"
      missing=1
    fi
  done

  return $missing
}

aik_doctor() {
  local required_tools=("$@")

  echo "AIK doctor"
  echo "os=$AIK_OS arch=$AIK_ARCH runtime=$AIK_RUNTIME image=$AIK_CONTAINER_IMAGE"

  if [ "$AIK_OS" = "macos" ] && [ -z "$AIK_IN_CONTAINER" ] && [ "$AIK_RUNTIME" != "native" ]; then
    if ! aik_has_docker; then
      echo "MISSING: docker CLI"
      return 1
    fi
    if ! aik_container_image_ready; then
      echo "Container image not found locally: $AIK_CONTAINER_IMAGE"
      echo "Run: docker build -t $AIK_CONTAINER_IMAGE $AIK_ROOT"
      return 1
    fi
    echo "container-ready"
    return 0
  fi

  if aik_check_required_tools "${required_tools[@]}"; then
    echo "native-ready"
    return 0
  fi

  echo "Install hints (macOS): brew install lzop xz lz4 u-boot-tools"
  return 1
}

aik_bootstrap() {
  local script_src="$1"
  shift

  AIK_ROOT="$(_aik_script_dir "$script_src")"
  AIK_SCRIPT_ABS="$AIK_ROOT/$(basename "$script_src")"

  aik_detect_platform

  : "${AIK_RUNTIME:=}"
  : "${AIK_STRICT_NATIVE:=0}"
  : "${AIK_CONTAINER_IMAGE:=$AIK_DEFAULT_CONTAINER_IMAGE}"
  AIK_FORWARDED=0

  aik_parse_common_args "$@"

  if [ -z "$AIK_RUNTIME" ]; then
    if [ "$AIK_OS" = "macos" ] && [ -z "$AIK_IN_CONTAINER" ]; then
      AIK_RUNTIME="container"
    else
      AIK_RUNTIME="auto"
    fi
  fi

  case "$AIK_RUNTIME" in
    native|auto|container) ;;
    *)
      echo "Invalid --runtime value: $AIK_RUNTIME (expected native|auto|container)" >&2
      return 2
      ;;
  esac

  if [ "$AIK_OS" = "macos" ] && [ -z "$AIK_IN_CONTAINER" ] && [ "$AIK_RUNTIME" != "native" ] && [ "$AIK_DOCTOR" != "1" ]; then
    if ! aik_has_docker; then
      echo "Docker is required on macOS for runtime=$AIK_RUNTIME" >&2
      return 1
    fi
    if ! aik_ensure_container_image; then
      return 1
    fi
    aik_exec_in_container "$AIK_SCRIPT_ABS" "$@"
    local forwarded_rc=$?
    [ $forwarded_rc -eq 0 ] && AIK_FORWARDED=1
    return $forwarded_rc
  fi

  return 0
}
