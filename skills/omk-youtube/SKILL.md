---
name: omk-youtube
description: "Extract and summarize YouTube video content via subtitle extraction. Triggered when user shares a YouTube link and wants a summary."
---

# YouTube Subtitle Extraction

## When to Use

User shares a YouTube URL and wants to understand the content (summary, key points, translation).

## Usage

```bash
# English subtitles (default)
bash skills/omk-youtube/scripts/yt-subtitle.sh "https://www.youtube.com/watch?v=XXXXX"

# Chinese subtitles
bash skills/omk-youtube/scripts/yt-subtitle.sh "https://www.youtube.com/watch?v=XXXXX" zh-Hans

# Save to file
bash skills/omk-youtube/scripts/yt-subtitle.sh "https://www.youtube.com/watch?v=XXXXX" en /tmp/subtitle.txt
```

## Workflow

1. Extract subtitles: `bash skills/omk-youtube/scripts/yt-subtitle.sh <url> [lang]`
2. Read the output (clean plain text, no timestamps)
3. Summarize in user's preferred language

## Tips

- For English videos: extract `en` subtitles, summarize in Chinese — best quality
- For Chinese videos: extract `zh-Hans` subtitles directly
- Priority: manual subtitles > auto-generated subtitles > auto-translated
- Requires: `yt-dlp` (`brew install yt-dlp`)
