# DROX Architecture

The Flutter source is organized by feature so Browser UI work stays isolated from Home, download handling, and app-wide notification setup.

## Structure

- `main.dart`: application bootstrap only.
- `app/drox_app.dart`: MaterialApp, theme, and top-level app preferences.
- `home/download_home.dart`: Home/download-list screen and its current download interactions.
- `browser/browser_page.dart`: embedded browser, tabs, navigation, history, and browser settings.
- `downloads/download_models.dart`: download-entry model and filter enum.
- `notifications/download_notifications.dart`: single-source download notification configuration.
- `shared/widgets/drox_widgets.dart`: reusable DROX visual widgets.

## Boundaries

- Browser owns its WebView controllers, tabs, history, and browser preferences.
- Home owns the download list and passes a download callback to Browser; Browser does not import or mutate Home state.
- Download models are shared through the downloads module.
- App bootstrap and notification configuration are outside the feature screens.
- Shared widgets contain presentation-only reusable components.

When extending the download engine, move its stateful orchestration into a dedicated downloads service/controller before adding more cross-feature dependencies. Keep feature communication through constructor callbacks and narrow public APIs.
