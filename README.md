<p align="center">
  <img src="assets/icon.png" width="110" alt="Mascot app icon">
</p>

<h1 align="center">mascot-screensaver</h1>

<p align="center">
  <b>Clawd, the Claude Code pixel mascot, lives on your desktop and keeps your Mac awake.</b><br>
  (Yes, it is technically the opposite of a screensaver.)
</p>

<p align="center">
  <img src="assets/clawd.png" width="300" alt="Clawd resting on the desktop">
</p>

If you run long AI-agent sessions (Claude Code and friends), macOS will happily sleep the display and lock the screen mid-run, so you come back to a password prompt instead of your agent's progress. Mascot holds a display-sleep assertion while a tiny pixel pet keeps you company.

macOS only. One small universal binary, no dependencies, no network access, no analytics.

## Features

- **Keeps the display awake** with a proper IOKit power assertion (`PreventUserIdleDisplaySleep`). Not a mouse jiggler: no fake input, nothing moves your cursor.
- **Authentic pixel Clawd**, faithful to the terminal art: official orange, terminal-accurate 1:2 pixel proportions, judgmental little eyes.
- **Alive**: breathes, blinks, glances around, and its eyes follow your cursor.
- **Idle antics**: stretches, foot shuffles, "thinking" sparkles, and the occasional coffee break.
- **Interactive**: hover for a blush and a wave, click for a happy hop, drag it anywhere (it tilts in your hand and lands with a squash).
- **Never in your way**: the window is click-through everywhere except Clawd's actual body, so it cannot block clicks on whatever is behind it.
- **Menu bar control** (✻): pause keeping-awake (Clawd visibly dozes off), ask for a wave or a coffee, reset position, launch at login, quit.
- Remembers where you left it, floats above full-screen apps, and shows its state at a glance:

| Caffeinating | On a break (keep-awake paused) |
|:---:|:---:|
| <img src="assets/coffee.png" width="240" alt="Clawd having coffee"> | <img src="assets/sleeping.png" width="240" alt="Clawd sleeping when keep-awake is paused"> |

## Install

### Download

1. Download `Mascot.app.zip` from the [latest release](../../releases/latest) and unzip it.
2. Drag `Mascot.app` into `/Applications`.
3. First launch: **right-click the app → Open** (it is ad-hoc signed, not notarized), or clear the quarantine flag:

   ```bash
   xattr -dr com.apple.quarantine /Applications/Mascot.app
   ```

Clawd appears at the top-right of your screen, and ✻ joins your menu bar.

### Build from source

Requires the Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/maulmota/mascot-screensaver.git
cd mascot-screensaver
./build.sh --install
```

`build.sh` compiles a universal binary, bundles the app, draws the icon, ad-hoc signs it, and (with `--install`) replaces `/Applications/Mascot.app` and relaunches it.

## Usage

| Action | Result |
|---|---|
| Hover Clawd | Blush, a little wave, and the close button appears |
| Click Clawd | Happy hop |
| Drag Clawd | Move it anywhere; position is remembered |
| ✻ → Keep Mac awake | Toggle the assertion. When off, Clawd dozes and the display may sleep |
| ✻ → Say hi / Coffee break | Ask for a trick |
| ✻ → Reset position | Send it back to the top-right corner |
| ✻ → Launch at login | Start with your Mac (macOS 13+) |

## How it works

Three files, no frameworks:

- **`MascotApp.swift`**: a borderless floating window plus a menu bar item. While enabled it holds `IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep, ...)`. It also polls the global mouse position at 20 Hz to flip `ignoresMouseEvents`, which is what makes the window click-through everywhere except the pet, and to feed cursor coordinates to the page for eye tracking.
- **`mascot.html`**: the entire pet. An SVG pixel grid plus a small behavior engine (idle scheduler, eye springs, typed label, particles). Swift streams pointer and drag data in; the page reports its clickable hitbox out.
- **`build-icon.swift`**: draws the app icon programmatically at build time.

Clawd's sprite geometry and the official body color, `rgb(215,119,87)`, were reconstructed from Claude Code's terminal art. Terminal quadrant "pixels" are twice as tall as they are wide, which is exactly why Clawd is this stout.

## Limitations

- It keeps your display on, which uses more power. Toggle it off from the menu when you do not need it.
- Corporate device-management (MDM) policies that force a screen lock can override display assertions.
- macOS 12 or later (launch at login requires macOS 13). macOS only, by design.

## Development

- `./start.command` runs the Swift source directly, no build step, for quick iteration.
- Art and behavior tuning live at the top of `mascot.html`: colors, event timing, and the label vocabulary.
- Open `mascot.html` in a browser to preview the pet; mouse movement and clicks stand in for the native cursor feed, and `?pose=coffee|think|stretch|shuffle|sleep|wave` triggers a pose for screenshots.

## Disclaimer

This is an unofficial fan project, not affiliated with or endorsed by Anthropic. Clawd, Claude, and Claude Code are Anthropic's trademarks; Clawd's pixel likeness is lovingly recreated here as fan art for a very good terminal crab.

## License

[MIT](LICENSE)
