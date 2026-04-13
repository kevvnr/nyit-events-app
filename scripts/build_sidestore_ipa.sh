#!/usr/bin/env bash
# Wrapper — unsigned builds live in build_ipa_campusapp_unsigned.sh
exec "$(cd "$(dirname "$0")" && pwd)/build_ipa_campusapp_unsigned.sh" "$@"
