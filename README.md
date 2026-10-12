# Digify

<p align="center">
  <strong>Small camera energy. Full-resolution files.</strong><br>
  A native iOS photo editor for a Canon PowerShot ELPH 360 HS A-inspired look.
</p>

Digify takes a photo from your library or Files, applies an in-camera-style treatment on device, and saves a full-resolution result. The target camera is JPEG-only; Digify can develop supported DNG/Apple ProRAW inputs before applying the look. It does not claim that an edited photo was captured by a Canon camera.

## Status

The project is under active development. There is no published release yet. When the first tagged release is published, these links will resolve:

- **Direct IPA:** [Download Digify.ipa](https://github.com/hesm4tt/Digify/releases/latest/download/Digify.ipa)
- **SideStore source:** [digify.json](https://github.com/hesm4tt/Digify/releases/latest/download/digify.json)
- **Releases and source:** [github.com/hesm4tt/Digify](https://github.com/hesm4tt/Digify)
- **Project site:** [hesm4tt.github.io/Digify](https://hesm4tt.github.io/Digify/), after GitHub Pages is enabled for this repository

## Install on a test device

Release IPAs are **unsigned**. The direct IPA URL downloads the package; it does not install it by itself. You need a compatible sideloading tool and must sign the app with your own Apple account or certificate. Signing and refresh limits are controlled by your installer and Apple account.

### SideStore

1. Install and set up SideStore on the device using [SideStore's official guide](https://docs.sidestore.io/).
2. In SideStore, add the source URL `https://github.com/hesm4tt/Digify/releases/latest/download/digify.json`.
3. Install Digify from the source. SideStore will sign it as part of installation.

If you prefer manual import, download `Digify.ipa` from the release and use SideStore's IPA import flow.

### LiveContainer

1. Install and configure [LiveContainer](https://github.com/LiveContainer/LiveContainer) using its current setup instructions.
2. Download `Digify.ipa` from the release, then import it into LiveContainer.

LiveContainer support and app behavior depend on the LiveContainer version and its supported iOS/device configuration. The IPA remains unsigned; follow LiveContainer's current signing and import instructions.

## Build from source

Open the Xcode project in Xcode and build the `Digify` scheme for an iOS 16 or later device. The tagged-release workflow builds an unsigned archive on a GitHub-hosted macOS runner and packages it as `Digify.ipa`.

To create the same package locally after archiving:

```sh
scripts/package-unsigned-ipa.sh /path/to/Digify.xcarchive /path/to/Digify.ipa
```

The packaging helper checks that the archived app uses bundle ID `com.hesm4tt.digify`. The SideStore feed generator reads the app's version and minimum OS version from the IPA:

```sh
scripts/make-sidestore-feed.sh /path/to/Digify.ipa /path/to/digify.json v1.0.0
```

## Releases

Push a version tag such as `v1.0.0` to build and publish a GitHub Release. The workflow attaches `Digify.ipa` and `digify.json`. It uses only the repository-provided `GITHUB_TOKEN`; no signing secrets are required. GitHub Pages deploys the contents of `docs/` from the `main` branch when Pages is configured to use GitHub Actions.

## Privacy

Image selection, processing, and export are designed to happen on device. The app does not need a Digify account or a photo upload service.

## License

Digify's source code is provided under the MIT License; see [LICENSE](LICENSE).
