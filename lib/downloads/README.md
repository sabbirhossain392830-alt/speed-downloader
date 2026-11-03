# DROX Download System v2

The replacement download architecture is isolated from the browser UI.

- core/: download entities and persistence contracts
- engine/: adapter for the native background transfer engine
- services/: network metadata and file services
- controllers/: state orchestration for download screens
- screens/ and widgets/: download-only presentation
- youtube/: YouTube URL parsing and metadata models

YouTube support is intentionally limited to link detection and public oEmbed
preview metadata. DROX does not extract YouTube media streams or bypass
YouTube's download restrictions. Direct media downloads are for URLs the user
owns or is authorized to download.
