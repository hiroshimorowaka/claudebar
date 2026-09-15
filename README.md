# claudebar

claudebar shows how much of your Claude AI plan you have used, in the GNOME taskbar. It shows the session limit, the weekly limit and the per-model limits. Each one has a progress bar, a color for the level of use, and the time until it resets.

The taskbar shows the Claude glyph and a short usage percentage. A click opens a card with one section for each limit.

<p align="center">
  <img src="screenshots/panel.png" alt="The claudebar usage card" width="340">
</p>

It is built for a GNOME X11 desktop, such as Zorin OS or Ubuntu on Xorg, with [Quickshell](https://quickshell.org) for the card and a small GNOME Shell extension for the taskbar icon.

## Contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Usage](#usage)
- [Configuration](#configuration)
- [How it works](#how-it-works)
- [Troubleshooting](#troubleshooting)
- [Uninstall](#uninstall)
- [Credits](#credits)

## Features

- Session (5h) and weekly (7d) limits, each with a countdown to the reset.
- Per-model limits, such as a weekly limit for one model, when the API reports them.
- Extra usage: the money spent this month, the prepaid balance that is left, and the monthly limit.
- Pace indicators that compare your use with the time that has passed, with a marker on each meter.
- A color gauge along each meter: green at 0%, amber in the middle, red at the top. Each number takes the color of the gauge at its own value.
- Meters that sweep from zero every time the card opens.
- An alert dot on the taskbar icon when a limit that is *not* on the taskbar reaches 90% or more, with a tooltip that names it.
- A pause mark on the taskbar icon while the widget shows cached data.
- Mouse and keyboard controls, plus IPC for keybinds and scripts.
- Works with the taskbar at the top or at the bottom of the screen.
- One JSON config for behavior, colors, fonts, sizes, corner radius and border, reloaded live.

## Requirements

- GNOME Shell on **X11**. GNOME on Wayland does not let Quickshell place the card over other windows.
- [Quickshell](https://quickshell.org/docs/guide/install-setup/) 0.3 or later, with X11 support (the default build).
- [Claude CLI](https://github.com/anthropics/claude-code). You must be logged in with the `claude` command.
- A Claude Pro or Max subscription.
- `curl`, `jq`, `python3`, `unzip` and GNU `date`. These are standard on most Linux systems.
- A [Nerd Font](https://www.nerdfonts.com/) for the footer and button glyphs. The default is JetBrainsMono Nerd Font.
- Optional: `xclip`, for the button that copies the CLI install command.

The installer also installs these two, if they are missing:

- The [`claudebar` CLI](https://github.com/mryll/claudebar), which fetches the usage data, into `~/.local/bin`.
- [Font Awesome](https://fontawesome.com/) 7 Brands, for the Claude glyph, into `~/.local/share/fonts/claudebar`.

## Installation

```bash
git clone https://github.com/hiroshimorowaka/claudebar.git ~/projects/widgets/claudebar
cd ~/projects/widgets/claudebar
./install.sh
```

The installer:

1. Checks the requirements, and installs the `claudebar` CLI and the Font Awesome Brands font if they are missing.
2. Links `quickshell/` to `~/.config/quickshell/claudebar` and `gnome-extension/` to `~/.local/share/gnome-shell/extensions/claudebar@hiroshi`. The files stay in the repository, so a `git pull` updates the widget.
3. Creates `~/.config/claudebar/config.json` from `config.example.json`. It never replaces a config that exists.
4. Starts the widget and adds `~/.config/autostart/claudebar.desktop`, so it starts with your session.
5. Enables the GNOME extension.

You can run the installer again at any time. It keeps your config.

GNOME Shell loads a new extension only after a restart. Press `Alt+F2`, type `r` and press `Enter`. Your windows stay open.

## Usage

| Control | Result |
|---|---|
| Left click on the icon | Open or close the card |
| Middle click on the icon | Get new data now. This ignores the 60-second cache. |
| Right click on the icon | Open the claude.ai usage page |
| `r`, `Enter` or `Space`, in the card | Get new data now |
| `Esc`, or a click outside the card | Close the card |
| `Up` / `Down` or `k` / `j`, in the card | Scroll, when the card is taller than the screen |

The footer of the card shows the time of the last update and a refresh button (󰑐). The button stays disabled while a fetch runs.

The widget answers IPC, so a GNOME custom shortcut or a script can drive it:

```bash
qs -p ~/.config/quickshell/claudebar ipc call claudebar refresh   # fetch now
qs -p ~/.config/quickshell/claudebar ipc call claudebar close     # close the card
```

`toggleAt <x> <edge> <size> <top|bottom>` opens the card at a position on the screen. The extension calls it with the icon position.

## Configuration

Edit `~/.config/claudebar/config.json`. The widget reloads it when you save. A key that is missing takes its default value.

```json
{
  "refreshIntervalSec": 300,
  "barWindow": "session",
  "showLabel": true,
  "colors": "full",

  "style": {
    "fontFamily": "JetBrainsMono Nerd Font",
    "fontSize": 12,
    "width": 340,
    "padding": 14,
    "gap": 5,
    "radius": 0,
    "borderWidth": 2,
    "border": "#cacccc",
    "background": "#101315",
    "backgroundOpacity": 1.0,
    "foreground": "#cacccc",
    "urgent": "#a55555",
    "brand": "#d97757"
  },

  "gauge": {
    "low": "#98c379",
    "mid": "#e5c07b",
    "high": "#d19a66",
    "critical": "#e06c75"
  }
}
```

### Behavior

| Key | Type | Default | Description |
|---|---|---|---|
| `refreshIntervalSec` | integer (60 or more) | `300` | How often to run `claudebar`. The API response stays in the cache for 60 seconds. A value of less than 300 can cause API rate limits. Opening the card always gets new data. |
| `barWindow` | `session` \| `weekly` | `session` | The limit that gives the percentage on the taskbar. Other limits still reach you through the alert dot and the card. |
| `showLabel` | boolean | `true` | Show the usage percentage next to the icon. |
| `colors` | `full` \| `none` \| `bar-only` \| `panel-only` | `full` | Where color is used. A monochrome surface uses only foreground tones. The numbers and the marks continue to show the level. |

### Style

| Key | Default | Description |
|---|---|---|
| `fontFamily` | `JetBrainsMono Nerd Font` | Font of the card, the taskbar label and the tooltip. Use a Nerd Font, for the glyphs. |
| `fontSize` | `12` | Base font size in pixels. Every other size and space in the card scales with it. |
| `width` | `340` | Width of the card, at a font size of 12. |
| `padding` | `14` | Space inside the card border, at a font size of 12. |
| `gap` | `5` | Space between the card and the taskbar or the screen edge, at a font size of 12. |
| `radius` | `0` | Corner radius of the card, the buttons and the tooltips, in pixels. |
| `borderWidth` | `2` | Width of the card border, in pixels. `0` removes the border. |
| `border` | `#cacccc` | Color of the card border. |
| `background` | `#101315` | Background of the card and the tooltips. |
| `backgroundOpacity` | `1.0` | Opacity of the card background, from `0` to `1`. |
| `foreground` | `#cacccc` | Text color. The dim texts, the separators and the meter tracks derive from it. |
| `urgent` | `#a55555` | Color of errors and of a pace that is much too fast. |
| `brand` | `#d97757` | Color of the Claude glyph in the card. |

### Gauge

The four colors of the meter gauge: `low` at 0%, `mid` at 50%, `high` at 75% and `critical` at 90% and above. A percentage between two of these takes a color between them. The widget sends these colors to the `claudebar` CLI, so the gauge and the thresholds come from one place.

## How it works

1. The `claudebar` CLI reads the OAuth credentials from `~/.claude/.credentials.json`. The Claude CLI writes that file.
2. The CLI refreshes the access token if the token expires in less than 5 minutes, and calls `api.anthropic.com/api/oauth/usage` for the usage data.
3. The widget runs `claudebar --json` in Quickshell at each refresh, and draws the card from the structured output.
4. The widget writes what the taskbar icon shows, the label, the colors, the marks and the tooltip, to `$XDG_RUNTIME_DIR/claudebar.json`.
5. The GNOME extension watches that file, draws the icon, and calls the widget IPC when you click.

```
quickshell/
  shell.qml       entry point: IPC and the state for the taskbar icon
  Theme.qml       reads the config
  Usage.qml       runs the CLI and builds the model: windows, gauge, pace, freshness
  Panel.qml       content of the card
  Popup.qml       the window that holds the card next to the icon
  IconButton.qml  small glyph button with a tooltip
gnome-extension/  the taskbar icon
install.sh        install, update and uninstall
```

> [!WARNING]
> The OAuth usage endpoint is not documented and has strict rate limits. An interval of less than 300 seconds will usually cause HTTP 429 errors. If this occurs, the widget shows the data from the cache with a pause mark. Refer to [claude-code#30930](https://github.com/anthropics/claude-code/issues/30930).

## Troubleshooting

| You see | Meaning | What to do |
|---|---|---|
| A dim icon with no percentage | The widget is getting the first data | This is normal at start. The data appears at the next refresh. |
| A pause mark after the percentage | Old data. The API applied a rate limit, or the network is down. | The widget shows the data from the cache. This corrects itself. |
| "Log in with the claude CLI" in the card | No credentials | Run `claude` to log in |
| An HTTP error at the bottom of the card | API error behind data that is still usable | Examine your internet connection. A 4xx error usually needs a new login. |
| "claudebar not found on PATH" in the card | The CLI is not installed | Run `./install.sh` again, or copy the command with the button in the card |
| No icon in the taskbar | The extension is not loaded | Restart GNOME Shell with `Alt+F2`, `r`. Then run `gnome-extensions info claudebar@hiroshi`. |
| The icon does nothing on click | The widget is not running | Run `qs -p ~/.config/quickshell/claudebar -d` |

**The card ignores my keyboard.** Click once inside the card, then use the keys.

**The Claude glyph is a box.** Run `fc-list | grep "Font Awesome 7 Brands"`. If it prints nothing, run `./install.sh` again.

**The widget logs.** Run `qs -p ~/.config/quickshell/claudebar log`.

## Uninstall

```bash
./install.sh --uninstall
```

This stops the widget, disables the extension, and removes the links and the autostart entry. It keeps `~/.config/claudebar/config.json`, the `claudebar` CLI and the font.

## Credits

- [claudebar](https://github.com/mryll/claudebar) by mryll: the CLI that fetches the usage data, and the usage model and meter design that this widget adapts.
- [Omarchy](https://github.com/basecamp/omarchy): the visual design of the card.

Both projects use the MIT license. Refer to [LICENSE](LICENSE).
