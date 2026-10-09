#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail
frames_dir=${1:?Provide the captured frame directory}
gif_path=${2:?Provide the output GIF path}
palette_file=$(mktemp /tmp/coversearch-gif-palette.XXXXXX.png)
trap 'rm -f "$palette_file"' EXIT
# Reserve one palette entry for optimized-frame transparency. A fixed gray ramp
# keeps the covers smooth instead of letting white UI areas dominate quantization.
magick -size 1x255 gradient:black-white -rotate 90 \
    '(' -size 1x1 xc:none ')' +append -depth 8 "$palette_file"
animation_args=()
while IFS=$'\t' read -r filename delay; do
    animation_args+=(-delay "$delay" "$frames_dir/$filename")
done < "$frames_dir/frames.tsv"
magick -dispose None "${animation_args[@]}" -resize 480x640 \
    -colorspace Gray -depth 8 +dither -remap "$palette_file" -layers Optimize -loop 0 "$gif_path"
magick identify -format '%n frames, %W × %H pixels\n' "$gif_path" | awk 'NR == 1'
