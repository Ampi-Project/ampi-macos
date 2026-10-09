# macOS prototype layout format

Status: local experimental draft, `schemaVersion: 1`. This is not the published cross-platform Ampi theme specification. It exercises native layout replacement while that independent specification project is developed.

The prototype reads a single JSON file, not a ZIP package. See the original [Retro Stereo](../Sources/AmpiCore/Themes/retro.json) and [Quiet Space](../Sources/AmpiCore/Themes/minimal.json) examples. Their geometry, arrangement, colors, and control corner radii differ.

## Fields

| Field | Meaning |
| --- | --- |
| `schemaVersion` | Must be 1 for this experimental reader |
| `id`, `name` | Short nonempty identity and display name |
| `width`, `height` | Fixed content size in macOS points; 320–1200 wide, 240–1000 high |
| `cornerRadius` | Control/panel corner radius from 0 to 24 |
| `palette` | `background`, `panel`, `text`, `muted`, and `accent` as `#RRGGBB` |
| `elements` | Between 1 and 64 elements, each with a unique `id` |

Each element specifies `kind`, `frame: [x, y, width, height]`, and `label`. Coordinates start at the top-left of the content surface. All rectangles must be finite, positive-sized, and contained within the content bounds.

| Kind | Semantics |
| --- | --- |
| `label` | Static `label`, or a `binding` of `track`, `time`, or `status`; optional `fontSize` 10–40 |
| `button` | `action`: `open`, `previous`, `playPause`, `stop`, `next`, `shuffle`, or `repeat`; minimum hit region 32 × 28 |
| `slider` | `binding`: `position` or `volume`; minimum 60 × 20 |
| `queue` | One queue maximum; height at least 60 points; double-click activates a track |

Every layout must expose Open and Play/Pause. Optional Shuffle/Repeat buttons show live On/Off and Off/All/One values; Repeat cycles Off → All → One → Off. Native application menus provide additional transport actions and Restore Default independently of the theme. Files over 256 KiB, invalid versions/colors/frames/actions, and missing required controls are rejected before replacement. The previous interface stays active on validation failure.

Load a file with **File → Open Skin / Layout…** or by dropping one JSON file. Choosing a new layout does not recreate the playback session or audio backend. There are no external assets, executable scripts, live reload, animations, transparent shapes, or archive import in this draft. Views currently have a fixed size and retain the native title bar.

## Legacy skins

The JSON reader is separate from the bounded [Classic importer](CLASSIC-INSPECTION.md), which inspects `.wsz`, ZIP, and extracted folders and offers explicit activation after the documented artwork profiles pass. Modern XML/MAKI packages remain unsupported and are rejected explicitly rather than treated as audio or native layouts.

The renderer uses custom AppKit buttons and backgrounds together with native sliders and queue controls. This is a feasibility prototype; full asset-driven rendering and complete accessibility/keyboard conformance require later work. Do not advertise it as a complete skin engine.
