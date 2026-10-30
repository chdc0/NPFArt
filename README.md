# NowPlayingFullArt

Full-screen Lock Screen artwork for Spotify on iOS 26/27, including tracks that
have no Canvas.

Written because EeveeSpotify 7.0.0 exposes Spotify's own
`ios-feature-lockscreen.animated_artwork_enabled` flag (Settings → Spotify
Features → Lock Screen → **Animated artwork**) but has no fallback: if a track
has no Canvas video, the Lock Screen stays small. This dylib adds the 8SPINE
trick — synthesise a 3:4 artwork from the static cover, so every track gets the
full-screen treatment.

Spotify is not patched or re-signed beyond the normal graft. The dylib only
swizzles `-[MPNowPlayingInfoCenter setNowPlayingInfo:]` inside the Spotify
process and adds one key to the dictionary Spotify was already sending.

## How it works

iOS 26 added two now-playing keys, `MPNowPlayingInfoProperty3x4AnimatedArtwork`
(3:4 portrait = full screen) and `...1x1...` (square). Each takes an
`MPMediaItemAnimatedArtwork`, built from a preview image handler and a video
file URL handler. The system falls back to the preview image while the video
loads, and under Low Power Mode, Low Data Mode, thermal pressure, Reduce Motion,
or Auto-Play Animated Images off.

Per currently-playing track:

1. Read `MPMediaItemPropertyArtwork` from the now-playing dictionary.
2. Compose a 3:4 image: the cover blurred and aspect-filled as a background,
   with the square cover centred on top at 92% width (no cropping of the art).
3. On request, render a 3 s seamlessly looping H.264 zoom (720×960) into
   `Library/Caches/NowPlayingFullArt/<id>.mp4`, once per artwork.
4. Attach the result under `MPNowPlayingInfoProperty3x4AnimatedArtwork`.

Identity for the cached artwork comes from
`MPNowPlayingInfoPropertyExternalContentIdentifier` (Spotify supplies the track
URI), falling back to artist/album/title.

## Build

Needs macOS + **Xcode 26 or newer** (the iOS 26 SDK). No Theos, no Orion, no
package manager.

```sh
./build.sh
```

Outputs:

| File | Behaviour |
|---|---|
| `out/NowPlayingFullArt.dylib` | **fallback** — only when Spotify supplied no animated artwork, so real Canvases win |
| `out/NowPlayingFullArt-always.dylib` | **always** — replaces Spotify's artwork too, Canvas or not |

Without a Mac, push this folder to a GitHub repo and run the
`build-dylib` workflow (Actions → Run workflow). It builds both dylibs on a
macOS runner and uploads them as the `NowPlayingFullArt` artifact.

## Graft into a Spotify build

Windows, from the `ytuhd` directory:

```powershell
.\tools\build_spotify_fullart.ps1 -Dylib .\nowplaying-fullart\out\NowPlayingFullArt.dylib
```

or by hand:

```powershell
$ee = "debs\upstream\spotify\root\var\jb\Library"
python tools\graft_payload.py `
  --ipa "D:\com.spotify.client-9.1.88.ipa" `
  --out "build\spotify-9.1.88-noext-fullart" `
  --no-extensions --strip-design-compat `
  --dylib "EeveeSpotify.dylib=$ee\MobileSubstrate\DynamicLibraries\EeveeSpotify.dylib" `
  --dylib "NowPlayingFullArt.dylib=out\NowPlayingFullArt.dylib" `
  --framework "$ee\Frameworks\EeveeSwiftProtobuf.framework=EeveeSwiftProtobuf.framework" `
  --framework "debs\upstream\orion\root\var\jb\Library\Frameworks\Orion.framework=Orion.framework" `
  --framework "build\21.43.5-graft\Payload\YouTube.app\Frameworks\CydiaSubstrate.framework=CydiaSubstrate.framework" `
  --bundle "$ee\Application Support\EeveeSpotify.bundle=EeveeSpotify.bundle" `
  --load "@rpath/EeveeSpotify.dylib" --load "@rpath/NowPlayingFullArt.dylib"

tools\bin\zsign.exe -a -f "build\spotify-9.1.88-noext-fullart\Payload\Spotify.app"
python tools\verify_seal.py "build\spotify-9.1.88-noext-fullart\Payload\Spotify.app"
python tools\pack_ipa.py "build\spotify-9.1.88-noext-fullart" "out\Spotify-9.1.88-fullart-adhoc.ipa"
```

Two extra load commands cost 112 bytes of the ~131 KB header slack, so the
one-App-ID, extension-free property of the build is unchanged.

## Tuning

`NPAConfig` at the top of `Sources/NowPlayingFullArt.swift`:

| Setting | Default | Notes |
|---|---|---|
| `animate` | `true` | `false` renders a 2-frame still — cheaper, still full screen |
| `loopSeconds` | `3.0` | length of the zoom loop |
| `zoomAmplitude` | `0.05` | 5% zoom, zero velocity at the loop seam |
| `previewSize` | 900×1200 | must stay 3:4 or the system discards it |
| `videoSize` | 720×960 | must stay 3:4 |

## Interplay with Canvas

- With a Canvas: `fallback` build does nothing, Spotify's video plays as it does
  now. `always` build overrides it with the synthesised zoom.
- Without a Canvas (most catalogue): `fallback` build gives full-screen art.
- If `MPNowPlayingInfoCenter.supportedAnimatedArtworkKeys` does not contain the
  3:4 key, the dylib no-ops.

## Status

Source only — **not compiled or tested**. The iOS 26 API surface was verified
against the mangled symbol Spotify itself uses
(`$sSo26MPMediaItemAnimatedArtworkC11MediaPlayerE9artworkID26previewImageRequest…`),
which decodes to
`init(artworkID:previewImageRequestHandler:videoAssetFileURLRequestHandler:)`
taking `(CGSize) async -> UIImage?` and `() async -> URL?`. Expect one round of
fixups on the first build.
