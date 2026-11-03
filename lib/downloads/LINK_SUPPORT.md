# DROX Link Support

DROX uses a provider-aware link resolver before adding a task to the background download queue.

## Active support in this build

- Direct HTTP/HTTPS file URLs with recognized file extensions.
- Public Google Drive file links: prepares the public `uc?export=download&id=...` URL. Google permission/confirmation pages can still prevent a direct transfer.
- Public Dropbox shared links: changes the documented `dl=0`/preview option to `dl=1`.
- Public OneDrive share links: adds the `download=1` option where supported.
- HTTP response inspection for supported cloud links: checks status, MIME type, content length and Content-Disposition filename. HTML pages are not incorrectly queued as files.
- GitHub release pages: public GitHub API lookup can queue a release automatically only when exactly one public asset exists; releases with multiple assets ask the user to choose on GitHub. Direct release asset URLs are supported.\n- Internet Archive item pages: public metadata lookup can queue automatically only when exactly one supported downloadable file exists; multi-file items ask the user to choose a file on the Archive page. Direct Archive download URLs are supported.\n- MediaFire, MEGA, Box, pCloud, TeraBox, WeTransfer and common video platforms are recognized and opened for their own authorized download flow; they are not falsely advertised as direct-download support.

## Recognized providers / future adapters

Google Drive, Dropbox, OneDrive, MEGA, MediaFire, Box, pCloud, TeraBox, WeTransfer, 4shared, Yandex Disk, Sync.com, Koofr, Send Anywhere, Wormhole, Smash, Vimeo, Dailymotion, YouTube, Facebook, Instagram, TikTok, Twitch, Reddit, X, GitHub, GitLab, SourceForge and Internet Archive.

Recognition does not mean every URL is downloadable. Each provider may require a public share permission, official API, sign-in, region availability, expiry validity or a provider-specific adapter.

## Safety and compatibility

- Only HTTP/HTTPS URLs are accepted by the download engine.
- DROX does not bypass login, private-share permissions, DRM, paywalls, or platform download restrictions.
- Video-host links are metadata/open-page only unless the provider supplies an authorized downloadable file URL.
- HLS/DASH manifests, FTP/SFTP, WebDAV, torrent and encrypted cloud formats are not enabled in this first adapter pass; they need separate protocol implementations and testing.
- BrowserPage is intentionally untouched.

## Next adapters

1. Official API / OAuth based support for Box, MEGA, pCloud and other cloud providers.\n2. Provider-specific public transfer adapters for MediaFire and WeTransfer.
2. Provider-specific public transfer adapters for MediaFire and WeTransfer.
3. Archive and streaming formats only where the host explicitly authorizes downloading.
4. Integration tests with public sample files and expired/permission-denied links.
