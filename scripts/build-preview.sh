#!/bin/bash
# Compatibility entry point for the former local preview.
set -euo pipefail
exec "$(dirname "$0")/build-picline.sh" "${1:-debug}"
