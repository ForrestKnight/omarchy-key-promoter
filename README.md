# Omarchy Key Promoter

[Key Promoter X](https://plugins.jetbrains.com/plugin/9792-key-promoter-x), but for your desktop.
Reach for the Omarchy menu to do something that already has a keybinding, and a small
toast shows you the shortcut. It uses **your** bindings, not Omarchy's defaults,
so every override in `~/.config/hypr/bindings.lua` is reflected.

The toast is drawn by the Omarchy shell with the shell's own theme tokens (popup
background, border, accent, font, corner radius), so it matches whatever theme is active
and follows `omarchy theme set` instantly.

https://github.com/user-attachments/assets/06ec77e3-3ab2-4406-ab90-7ce99275f386

## Install

```bash
omarchy plugin add https://github.com/ForrestKnight/omarchy-key-promoter.git --enable --yes
```

Or by hand: copy this directory to `~/.config/omarchy/plugins/fkcodes.key-promoter/`, then

```bash
omarchy-shell shell rescanPlugins
omarchy plugin enable fkcodes.key-promoter
```

## Remove

```bash
omarchy plugin remove fkcodes.key-promoter
```

That deletes the plugin directory and its shell.json entry. The only other file it ever
writes is `~/.local/state/omarchy/key-promoter.json` (promotion counts); delete it if you
want a clean slate.

## Dependencies and privileges

Nothing beyond a stock Omarchy install: `omarchy-menu-keybindings`, `hyprctl`, `jq`, `ps`,
`inotifywait` (inotify-tools, in Omarchy's base packages). No sudo, no network; the only
long-lived helper is one `inotifywait` watching a cgroup directory, see below. It never edits Hyprland or shell configuration; the only
config it touches is its own inline entry in `shell.json`, and only when you edit it.

## How it decides to speak up

The plugin never sees key presses. It listens to Hyprland events and only pays
attention for a few seconds after the Omarchy menu closes. In that window:

| What happened next                       | Matched against                                    |
|------------------------------------------|----------------------------------------------------|
| A window opened (app or web app)         | binds that launch that app / `--app=` URL          |
| A shell layer opened (emojis, clipboard) | binds that toggle that shell plugin                |
| An `omarchy-*` script started            | binds that run that script (screenshot, lock, ...) |

Nothing happened, or the menu was dismissed with Escape: no toast. Launching with the
keybinding itself never triggers a toast, because the menu wasn't involved.

Closing the menu alone is not proof the menu did it: dismissing it with Escape and then
pressing a shortcut right away looks identical in Hyprland's event stream. So the launch
also has to show it came from the shell:

- **Windows.** The menu's app list is the only thing in Omarchy that starts apps through
  `uwsm-app -- gtk-launch`, and systemd registers that as a scope named
  `app-*-gtk\x2dlaunch-*.scope`. An `inotifywait` on the user's `app-graphical.slice`
  cgroup directory sees that scope appear a moment before the window does. No scope, no
  toast. (Tracing the window back to a process would not work: a new Chromium window
  belongs to the browser that was already running, however it was asked for.)
- **Scripts.** A process the shell started inherits the shell's environment, which
  `omarchy-launch-shell` marks with `QS_*` variables Hyprland's own environment never has.
  The process scan only counts `omarchy-*` scripts that carry the marker.
- **Layers** (emojis, clipboard) leave no trace either way, so those still rely on the
  time window alone.

If the watcher cannot run or the marker is absent, the plugin falls back to the time window.
`omarchy-shell key-promoter state` shows which checks are active.

When several bindings do the same thing, the one with the fewest modifiers wins.
Media keys (`XF86Calculator`, `XF86Mail`, ...) are never promoted: they are labeled hardware
buttons, not shortcuts to learn, and many keyboards lack them.

## Settings

Inline on the plugin entry in `~/.config/omarchy/shell.json` (hot-reloads on save):

```json
{ "id": "fkcodes.key-promoter", "duration": 3500, "position": "bottom-right", "window": 3000, "showCount": true }
```

| Key         | Default | Meaning                                                   |
|-------------|---------|-----------------------------------------------------------|
| `duration`  | `3500`  | milliseconds the toast stays up                           |
| `position`  | `bottom-right` | `top-left`, `top-center`, `top-right`, `bottom-left`, `bottom-center`, `bottom-right`. Clears the bar on a shared edge. |
| `window`    | `3000`  | milliseconds after the menu closes during which a launch counts |
| `showCount` | `true`  | show `×N` for how often that shortcut has been promoted   |

## IPC

```bash
omarchy-shell key-promoter show "SUPER + B" "Browser"   # preview the toast
omarchy-shell key-promoter hide
omarchy-shell key-promoter reload                        # re-read bindings (also automatic on Hyprland config reload)
omarchy-shell key-promoter resolved                      # JSON: every bind it can match, with its launch signature
omarchy-shell key-promoter stats                         # JSON: promotion counts, persisted in ~/.local/state/omarchy/key-promoter.json
omarchy-shell key-promoter state                         # JSON: armed?, launch watcher running?, shell marker, ms since the app list last launched something
```

## Layout

```
manifest.json   service plugin, entry point Service.qml
Service.qml     Hyprland event watcher, settings, counts, IPC
Toast.qml       the themed card
Promoter.js     pure logic: bind -> launch signature, matching, key chips
bin/keybinds    exports the machine's effective bindings as JSON (reuses the resolver behind SUPER + K)
```

## Not covered yet

Workspace switches and other things done by clicking the bar. Bar widgets are first-party
code, so a plugin can't see those clicks; the same goes for menu actions that neither open
a window nor leave a process behind (nightlight toggle finishes before we can look).

Shell layers opened by shortcut within a few seconds of dismissing the menu with Escape can
still be misattributed to the menu; windows and scripts no longer are.

## License

MIT. See `LICENSE`.
