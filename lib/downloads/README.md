# DROX Download System v2

The replacement download architecture is isolated from the browser UI.

- core/: download entities and persistence contracts
- engine/: adapter for the native background transfer engine
- services/: network metadata and file services
- controllers/: state orchestration for download screens
- screens/ and widgets/: download-only presentation
- youtube/: YouTube URL parsing, quality-option models and saved download jobs

## YouTube downloads

Pasting or sharing a YouTube link (watch, youtu.be, shorts, music, embed, live
URL forms) opens a quality picker (`screens/youtube_quality_sheet.dart`). The
choice is downloaded by `services/youtube_stream_service.dart`, which uses the
`youtube_explode_dart` package to read the video's public stream list.

- Muxed MP4 (video + audio in one file) is offered first; it is the most
  reliable option and usually tops out at 720p.
- Higher qualities use a separate video stream and audio stream that are merged
  with FFmpeg (`-c copy`, no re-encoding).
- An audio-only option saves M4A (or WebM when no M4A exists).
- A fresh manifest is fetched for every stream, because YouTube often refuses a
  second download from the same manifest.
- Items are marked `isStream`: they can be cancelled and retried, not paused.
  A retry re-reads the saved `YoutubeJob` (video id + stream ids).

Not supported, and reported to the user instead of being worked around: live
streams, videos that need a purchase/rental or membership, private or removed
videos, and age-restricted videos. DROX does not sign in to YouTube.

YouTube's Terms of Service restrict downloading outside the features YouTube
provides, and Google Play does not accept apps that do this. This build is meant
for sideloaded APKs; only save videos you own or have permission to download.
