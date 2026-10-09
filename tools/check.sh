#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
bytecode=$(mktemp)
trap 'rm -f "$bytecode"' EXIT
shopt -s globstar nullglob
for source_file in coversearch.koplugin/**/*.lua tests/**/*.lua tools/**/*.lua; do
    luajit -b "$source_file" "$bytecode"
done
for suite in run isbn http cache localization; do
    luajit "tests/$suite.lua"
done
luajit tools/version.lua
