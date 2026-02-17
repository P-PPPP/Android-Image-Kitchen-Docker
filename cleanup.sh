#!/bin/bash
# AIK-Linux/cleanup: reset working directory
# osm0sis @ xda-developers

script_path="${BASH_SOURCE:-$0}";
script_dir="$(cd "$(dirname "$script_path")" && pwd -P)";
. "$script_dir/lib/runtime.sh";

AIK_REQUIRED_TOOLS=(cpio);
aik_bootstrap "$script_path" "$@" || exit $?;
[ "$AIK_FORWARDED" = "1" ] && exit 0;
if [ "$AIK_DOCTOR" = "1" ]; then
  aik_doctor "${AIK_REQUIRED_TOOLS[@]}";
  exit $?;
fi;
set -- "${AIK_ARGS[@]}";

case $1 in
  --help) echo "usage: cleanup.sh [--runtime native|auto|container] [--container-image <image>] [--strict-native] [--doctor] [--native] [--local] [--quiet]"; exit 1;
esac;

case $(uname -s) in
  Darwin|Macintosh) statarg="-f %Su";;
  *) statarg="-c %U";;
esac;

aik="${BASH_SOURCE:-$0}";
aik="$(dirname "$(aik_readlink_f "$aik")")";
bin="$aik/bin";

case $1 in
  --local) shift;;
  *) cd "$aik";;
esac;

aik_fix_permissions "$aik" "$bin";

if [ -d ramdisk ] && [ "$(stat $statarg ramdisk | head -n 1)" = "root" -o ! "$(find ramdisk 2>&1 | cpio -o >/dev/null 2>&1; echo $?)" -eq "0" ]; then
  if command -v sudo >/dev/null 2>&1; then
    sudo=sudo;
  fi;
fi;

$sudo rm -rf ramdisk split_img *new.* || exit 1;

case $1 in
  --quiet) ;;
  *) echo "Working directory cleaned.";;
esac;
exit 0;
