#!/bin/bash
set -e

script_dir="$(cd "$(dirname "${BASH_SOURCE:-$0}")" && pwd -P)"

exec "$script_dir/unpackimg.sh" --runtime container "$@"
