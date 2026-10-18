#!/usr/bin/env bash
# ABOUTME: Install the pinned Lean toolchain in the repository's ignored tools directory.
# ABOUTME: Keep the user's shell profile and global toolchain selection unchanged.
set -euo pipefail
cd "$(dirname "$0")/.."
export ELAN_HOME="$PWD/.tools/elan"
mkdir -p .tools
curl --fail --location --proto '=https' --tlsv1.2 \
  https://raw.githubusercontent.com/leanprover/elan/v4.1.2/elan-init.sh \
  --output .tools/elan-init.sh
sh .tools/elan-init.sh -y --no-modify-path --default-toolchain none
"$ELAN_HOME/bin/elan" toolchain install "$(cat lean-toolchain)"
"$ELAN_HOME/bin/lake" --version
printf '%s\n' 'Ready. For this terminal:' 'export ELAN_HOME="$PWD/.tools/elan"' 'export PATH="$ELAN_HOME/bin:$PATH"'
