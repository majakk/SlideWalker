# SlideWalker

**Present your slides by walking through them.**

**[⬇ Download the latest release](https://github.com/majakk/SlideWalker/releases/latest)** — Windows, macOS and Linux.

SlideWalker turns a PowerPoint deck into a 2D platformer. Open a `.pptx` file, pick a course
type, and your slides become the level: every text line, title and image is a real, walkable
ledge, laid out exactly as the deck's author placed it. Giving the presentation *is* walking,
jumping and climbing through it.

Built with [Godot 4.7](https://godotengine.org/), in GDScript, with no external dependencies for
parsing — `.pptx` files are read directly with Godot's built-in `ZIPReader`/`XMLParser`.

## Features

- **Faithful slide rendering.** Text styles, bullets, colors, fonts, images (with crop/rotation),
  shapes and backgrounds are read straight from the deck, following its slide → layout → master →
  theme chain — including inherited placeholder styles and theme colors.
- **Four course types**, picked in the start menu:
  - **Side-scroller** — slides left to right on one continuous floor.
  - **Climb up** — slides stacked bottom to top; jump through each slide's floor into the next.
  - **Drop down** — start on slide one's title and drop down through the deck.
  - **Spiral (big canvas)** — slides arranged on a 2D grid in a square spiral around the first
    slide; walk sideways to a row's neighbor, or jump/drop between rows to skip ahead or back.
- **Physics tuned to your deck.** The jump height is calibrated per presentation so every ledge is
  reachable — a normal jump handles most of it, and a double jump reaches the rest, including the
  top of the tallest slide.
- **A completability guarantee.** Every course has a solid floor (or, in climb/drop, a floor per
  slide) underneath the content, so a missed jump is never a dead end.
- **Two player styles** — a procedurally animated stick figure, or the classic
  Brackeys pixel-art knight — both with run, jump, double-jump, wave, and skid/landing dust.
- **Two camera modes** — frame one slide at a time with a pan on transitions, or scroll seamlessly
  with the player.
- **Pause and resume.** Esc opens the menu over your paused presentation; resume picks up exactly
  where you left off, unless you've chosen a different file or course type.
- **Optional elapsed-time clock** in the corner, off by default.

## Controls

| Action | Keyboard | Controller |
|---|---|---|
| Move | A / D | Left stick / D-pad |
| Jump (again in the air: double jump) | Space | A |
| Drop through the current ledge | S / Down | Down |
| Wave | Q | Y |
| Interact (slide links/media) | E | X |
| Toggle camera mode | C | — |
| Toggle timer | T | — |
| Pause / resume | Esc | — |

## Running it

### From a standalone build

Build Linux, Windows and macOS binaries with:
```
tools/export_all.sh
```
(needs the Godot export templates installed once — see the comment at the top of that script).
This produces `dist/SlideWalker-linux-x86_64.zip`, `dist/SlideWalker-windows-x86_64.zip` and
`dist/SlideWalker-macos.zip`.

These builds aren't code-signed. On first launch:
- **Windows** shows a "Windows protected your PC" SmartScreen warning — click **More info**, then
  **Run anyway**.
- **macOS** refuses to open it as "from an unidentified developer" — right-click (or Control-click)
  the app and choose **Open**, then confirm. If that doesn't work, clear the quarantine flag:
  `xattr -cr SlideWalker.app`.
- **Linux** needs the executable bit set: `chmod +x SlideWalker.x86_64`.

### From source

1. Install [Godot 4.7](https://godotengine.org/download) (or newer, same major version).
2. Open this folder as a project in the Godot editor, or run it from the command line:
   ```
   godot --path . res://world/course.tscn
   ```
3. From the start menu, choose a `.pptx` file, a course type and a player style, then
   **Start presenting**.

Godot's own import cache (`.godot/`) isn't committed. The first time you open the project, Godot
regenerates it automatically.

## Current limitations

- Only `.pptx` is supported for now (no `.odp`).
- Embedded video, animated GIFs, and click-to-reveal builds aren't played back yet.
- Tables render as an outline rather than their actual cell content.

## Credits

The pixel-art knight is from
[Brackeys' Platformer Bundle](https://brackeysgames.itch.io/brackeys-platformer-bundle)
(sprite by analogStudios_), licensed CC0. See
[`assets/brackeys/LICENSE_AND_CREDITS.txt`](assets/brackeys/LICENSE_AND_CREDITS.txt) for details,
including the two wave frames added for this project.
Special thanks to Ruken Gül Nazlican who inspired me to test this idea.

---

♥ If you enjoy this, please [buy the developer a coffee](https://buymeacoffee.com/mattiasjac9)!
