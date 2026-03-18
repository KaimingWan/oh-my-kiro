#!/bin/bash
# Extract YouTube subtitles as clean plain text
# Usage: yt-subtitle.sh <youtube_url> [lang] [output_file]
#   lang: subtitle language (default: en)
#   output_file: save to file instead of stdout
# Exit 0: success / Exit 1: error

set -euo pipefail

URL="${1:-}"
LANG="${2:-en}"
OUTPUT="${3:-}"

if [ -z "$URL" ]; then
  echo "Usage: yt-subtitle.sh <youtube_url> [lang] [output_file]" >&2
  echo "  lang: en (default), zh-Hans, ja, etc." >&2
  exit 1
fi

if ! command -v yt-dlp &>/dev/null; then
  echo "Error: yt-dlp not found. Install: brew install yt-dlp" >&2
  exit 1
fi

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Try manual subtitles first, then auto-generated
SUB_FILE=""
for FLAG in "--write-sub" "--write-auto-sub"; do
  yt-dlp $FLAG --sub-lang "$LANG" --sub-format srt --skip-download \
    -o "$TMPDIR/sub" "$URL" >&2 2>&1 || true
  SUB_FILE=$(ls "$TMPDIR"/sub*.srt 2>/dev/null | head -1)
  [ -n "$SUB_FILE" ] && break
done

# Fallback: if requested lang not found, try auto-translated from English
if [ -z "$SUB_FILE" ] && [ "$LANG" != "en" ]; then
  yt-dlp --write-auto-sub --sub-lang "${LANG}-en,en" --sub-format srt --skip-download \
    -o "$TMPDIR/sub" "$URL" >&2 2>&1 || true
  SUB_FILE=$(ls "$TMPDIR"/sub*.srt 2>/dev/null | head -1)
fi

if [ -z "$SUB_FILE" ]; then
  echo "Error: No subtitles found for lang=$LANG" >&2
  exit 1
fi

# Clean SRT: remove sequence numbers, timestamps, blank lines, deduplicate
CLEAN=$(sed '/^[0-9][0-9]*$/d; /^[0-9][0-9]:[0-9][0-9]:/d; /^$/d; s/<[^>]*>//g' "$SUB_FILE" \
  | awk '!seen[$0]++' \
  | tr '\n' ' ' \
  | sed 's/  */ /g; s/^ *//; s/ *$//')

if [ -n "$OUTPUT" ]; then
  echo "$CLEAN" > "$OUTPUT"
  echo "Saved to: $OUTPUT ($(echo "$CLEAN" | wc -w | tr -d ' ') words)" >&2
else
  echo "$CLEAN"
fi
