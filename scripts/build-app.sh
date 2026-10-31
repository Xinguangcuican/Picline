#!/bin/bash
# Build Picline for the current Mac.
set -euo pipefail
exec "$(dirname "$0")/build-picline.sh" "${1:-release}"
