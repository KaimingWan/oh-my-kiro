---
name: omk-youtube
description: "Extract and summarize YouTube video content via subtitle extraction. Trigger when user shares a YouTube URL (youtube.com or youtu.be), says 'summarize this video', 'watch this', '看看这个视频', or wants to understand video content without watching. Also trigger for video transcript extraction."
---

## Trigger Examples
- "帮我看看这个视频讲了什么 https://youtube.com/watch?v=xxx"
- "summarize this YouTube video"
- "提取这个视频的字幕"
- "这个 talk 讲了什么？ https://youtu.be/xxx"
- "translate this video's content to Chinese"

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
