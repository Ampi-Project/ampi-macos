# Classic main player — increment 3

Classic inspection now offers **Use Classic Skin**. Activation constructs and validates the replacement before attaching it to the existing player window. Music, queue identity, selected track, offset, gain, backend, observer, and refresh timer stay in the same session. Opening the inspector alone still leaves the current interface unchanged.

Increment 4 adds a separately validated [Classic playlist](CLASSIC-PLAYLIST.md). Both replacements are prepared before installation; first activation shows the panel, and the original native **PL** button or **⌘L** hides/reopens it.

This is a partial Classic main profile, not full Winamp compatibility. The main view is 550×232 logical points: 2× the original 275×116 background. Graphics use nearest-neighbor sampling. Six native buttons draw idle/pressed sprites and dispatch Previous, Play, Pause, Stop, Next, and Open Audio. Repeated Play stays playing; repeated Pause stays paused. Pause while stopped does nothing. Space retains the native menu's Play/Pause toggle behavior.

Seek and volume use native `NSSlider` input, keyboard, and accessibility with sprite-based cells when their optional sheets are present. Missing optional sheets fall back to native sliders. Track title, elapsed time, and status use readable native text, including Unicode filenames. Native window chrome provides dragging, closing, and minimizing; historical title-strip artwork is decorative.

The Apple backend clamps a final-position seek to the last audio sample. This prevents a paused exact-end seek from wrapping to zero; resuming there reaches the normal track-completion path. The whole-second clock may therefore show the preceding second at the far end.

## Activation geometry

Every supplied BMP first passes the bounded [inspection profile](CLASSIC-INSPECTION.md). Main activation additionally requires these crop extents:

| Sheet | Required dimensions | Behavior |
| --- | --- | --- |
| `main.bmp` | Exactly 275×116 | Required main background |
| `cbuttons.bmp` | At least 136×36 | Required transport artwork |
| `titlebar.bmp` | At least 302×29 when present | Optional active/inactive title strips |
| `posbar.bmp` | At least 307×10 when present | Optional seek track and idle/pressed thumbs |
| `volume.bmp` | At least 68×433 when present | Optional 28 gain backgrounds and idle/pressed thumbs |

Missing optional artwork is supported; present undersized sheets prevent activation and explain the failing dimensions. Some historical volume strips differ in width; this initial profile accepts the stated 68-pixel geometry only. No broader corpus claim has been made. Unknown assets are retained by inspection but not interpreted as executable code.

Sheet roles and coordinates were checked against [Alpha-II's original template documentation](https://www.alpha-ii.com/Info/Template.html) and [Webamp's primary sprite definitions](https://github.com/captbaritone/webamp/blob/master/packages/webamp/js/skinSprites.ts). Ampi's AppKit implementation and fixture artwork are independently written.

## Checks and limitations

See [manual acceptance steps](TESTING.md) and [fixture provenance](../Tests/AmpiUITests/Fixtures/README.md). Native control tests cover real selector dispatch, Unicode titles, separate Play/Pause semantics, slider callbacks, sprite pixels and thumb endpoints, missing optional fallbacks, undersized sheets, failed activation, and native/Classic replacement with session preservation. The developer smoke test also activates a skin during muted real-backend playback and restores the default interface.

```sh
swift build
swift test
bash scripts/build-app.sh
dist/Ampi.app/Contents/MacOS/Ampi --classic-player-preview Tests/AmpiUITests/Fixtures/playable-classic.wsz /tmp/ampi-classic-player.png
dist/Ampi.app/Contents/MacOS/Ampi --smoke-test /path/to/a-long-enough.wav Tests/AmpiUITests/Fixtures/playable-classic.wsz
```

The separate Classic playlist now provides queue browsing/activation and native transport. The [equalizer](CLASSIC-EQUALIZER.md) now provides native controls and real DSP. Historical EQ sprites/response graph/preset interchange, full historical playlist controls, balance, shuffle/repeat, visualization, original bitmap text/numbers, shade mode, custom window shapes, panel docking, alternate scales, managed installation, and theme persistence remain pending. Modern XML/MAKI remains a later milestone. Native labels exist, but a complete keyboard/VoiceOver review still needs human testing.
