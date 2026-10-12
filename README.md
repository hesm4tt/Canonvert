# Canonvert

<p align="center">
  <strong>Small camera energy. Full-resolution files.</strong><br>
  A native iOS photo editor for a Canon PowerShot ELPH 360 HS A-inspired look.
</p>

Canonvert takes a photo from your library or Files, applies an in-camera-style treatment on device, and saves a full-resolution result. Adjust color, contrast, warmth, flash lift, exposure, detail, and vignette; save custom looks locally for reuse. Take new photos with the built-in camera, see the entire 3:4 viewfinder with a 3 × 3 grid, and capture at maximum supported still-image quality; Apple ProRAW capture is available on supported iPhones (ProRes RAW is a video format). Keep the edited preview pinned above the scrolling customizer, then choose HEIC or JPEG and Camera Roll or a Files location on the export screen. The target camera is JPEG-only; Canonvert can develop supported DNG/Apple ProRAW inputs before applying the look. It does not claim that an edited photo was captured by a Canon camera.

## Status

The project is under active development. Version 1.0.4 clarifies the camera → customize → export flow: a full 3:4 viewfinder, pinned photo preview while you scroll through look controls, then explicit format and destination choices. The release assets are published from the `v1.0.4` tag.

- **Direct IPA:** [Download Canonvert.ipa](https://github.com/hesm4tt/Canonvert/releases/latest/download/Canonvert.ipa)
- **SideStore source:** [canonvert.json](https://github.com/hesm4tt/Canonvert/releases/latest/download/canonvert.json)
- **Releases and source:** [github.com/hesm4tt/Canonvert](https://github.com/hesm4tt/Canonvert)
- **Project site:** [hesm4tt.github.io/Canonvert](https://hesm4tt.github.io/Canonvert/).

## Install on a test device

Release IPAs are **unsigned**. The direct IPA URL downloads the package; it does not install it by itself. You need a compatible sideloading tool and must sign the app with your own Apple account or certificate. Signing and refresh limits are controlled by your installer and Apple account.

### SideStore

1. Install and set up SideStore on the device using [SideStore's official guide](https://docs.sidestore.io/).
2. In SideStore, add the source URL `https://github.com/hesm4tt/Canonvert/releases/latest/download/canonvert.json`.
3. Install Canonvert from the source. SideStore will sign it as part of installation.

If you prefer manual import, download `Canonvert.ipa` from the release and use SideStore's IPA import flow.

### LiveContainer

1. Install and configure [LiveContainer](https://github.com/LiveContainer/LiveContainer) using its current setup instructions.
2. Download `Canonvert.ipa` from the release, then import it into LiveContainer.

LiveContainer support and app behavior depend on the LiveContainer version and its supported iOS/device configuration. The IPA remains unsigned; follow LiveContainer's current signing and import instructions.

## Build from source

Open `Canonvert.xcodeproj` in Xcode and build the `Canonvert` scheme for an iOS 16 or later device. The tagged-release workflow builds an unsigned archive on a GitHub-hosted macOS runner and packages it as `Canonvert.ipa`.

To create the same package locally after archiving:

```sh
scripts/package-unsigned-ipa.sh /path/to/Canonvert.xcarchive /path/to/Canonvert.ipa
```

The packaging helper checks that the archived app uses bundle ID `com.hesm4tt.digify`. The SideStore feed generator reads the app's version and minimum OS version from the IPA:

```sh
scripts/make-sidestore-feed.sh /path/to/Canonvert.ipa /path/to/canonvert.json v1.0.0
```

## Releases

Push a version tag such as `v1.0.0` to build and publish a GitHub Release. The workflow attaches `Canonvert.ipa` and `canonvert.json`. It uses only the repository-provided `GITHUB_TOKEN`; no signing secrets are required. GitHub Pages deploys the contents of `docs/` from the `main` branch when Pages is configured to use GitHub Actions.

## Privacy

Image selection, processing, and export are designed to happen on device. The app does not need a Canonvert account or a photo upload service.

## License

Canonvert's source code is provided under the MIT License; see [LICENSE](LICENSE).
