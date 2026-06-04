# SketchBookPlayer

Minimal macOS shell for presenting generative `HTML/Canvas/WebGL` artworks in a dedicated player window.

## Current MVP

- Separate player window for the artwork
- Separate controller window for loading work
- Remote `http/https` URL loading
- Local `index.html` loading through a file picker
- Borderless, resizable player window with a thin translucent shell
- Reload action
- Always-on-top toggle
- Bundled sample artwork for smoke testing

## Structure

- `Package.swift`: Swift Package manifest
- `Sources/SketchBookPlayer/AppDelegate.swift`: app startup and window wiring
- `Sources/SketchBookPlayer/AppState.swift`: shared loading state
- `Sources/SketchBookPlayer/ControllerView.swift`: control panel UI
- `Sources/SketchBookPlayer/PlayerWindowController.swift`: player window and `WKWebView`
- `Sources/SketchBookPlayer/Resources/SampleWork/index.html`: sample artwork

## Run

This project is meant to be opened on a Mac with full Xcode installed, not just Command Line Tools.

1. Install Xcode.
2. Open the package folder in Xcode.
3. Run the `SketchBookPlayer` executable target.

## Local app bundle

To build a persistent local app bundle in `dist/awen.app`:

```bash
./scripts/package_local_app.sh
open ./dist/awen.app
```

## Next useful steps

- Load a whole artwork folder instead of only a single HTML file
- Persist recent artworks
- Add a tiny library view with previews and metadata
- Support query params / runtime controls for artworks
- Add a manifest format for title, preview, and default size
