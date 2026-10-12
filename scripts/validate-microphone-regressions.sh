#!/bin/bash
set -euo pipefail
script_directory="$(cd "$(dirname "$0")" && pwd -P)"
exec /usr/bin/ruby "${script_directory}/microphone-regression-gate.rb" "$@"
