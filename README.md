# Command Center

![Command Center home: last played media, date, live System & Network tile, and the Recently Used strip](docs/home.webp)

A Raycast-style launcher for [Omarchy](https://omarchy.org) — one palette in
front of every command, app, and system control your desktop exposes.

## Features

- **Search everything** — every omarchy command and installed app (367
  commands and 38 apps on the machine in these screenshots), ranked by usage
  and recency, with app icons throughout.
- **Universal providers** — calculator and unit conversion lead the results,
  with ask-an-agent and web search always one row behind. Window switcher,
  clipboard history, files, and dictionary rows appear as you type.
- **Home** — a fixed, non-shifting block: last played media, the date, and a
  live System & Network tile (ping, packet loss, throughput, IP, gateway,
  CPU) above a Recently Used strip. The dashboard never refreshes on a timer;
  the network tile ticks only while the palette is open. The strip never
  shows one app or command twice, and re-launching promotes it to the front.
- **Groups** — Pinned favorites, Apps with icons, Controls (live status
  readouts plus quick actions with confirmations), History (a launch
  timeline), and News (RSS with feeds you edit in your own editor).
- **Power and session** — sleep, lock, logout, and shutdown from one popover,
  with confirmation on the destructive ones.
- **Super+Space parity** — everything Omarchy's own menu exposes, held in
  place by a test that byte-matches the plugin's action strings against
  `omarchy-menu.jsonc`, so an Omarchy update cannot silently drift it.
- **Bar widget** — a launcher button for the status bar: left click opens the
  palette, right click opens a terminal.

## Screenshots

| Search with the detail pane | Inline calculator |
| --- | --- |
| ![Searching "theme" with the ACTION detail card](docs/search.webp) | ![Typing 12 * 7 gives 84 with a copy action](docs/calc.webp) |

| Controls group | News group |
| --- | --- |
| ![Controls: live battery, volume, CPU, and connection readouts above quick actions](docs/controls.webp) | ![News: RSS stories from the configured feeds](docs/news.webp) |

The launch timeline lives in the History group:

![History: every launch with count and age](docs/history.webp)

## Installation

```
omarchy plugin add https://github.com/AkinleyeMicheal/omarchy-command-center.git --enable
```

Optional bar widget next to the Omarchy menu:

```
omarchy bar put fonsgaudii.cmdcenter --after omarchy.menu
```

## Keybinding

The palette summons through the shell, so any Hyprland binding works. In
`~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + SHIFT + K", "Command center", "omarchy-shell shell toggle fonsgaudii.cmdcenter")
```

## Uninstallation

```
omarchy plugin remove fonsgaudii.cmdcenter
```

## Development

```
omarchy plugin validate .
omarchy restart shell
for t in tests/*.test.js; do node "$t"; done
for t in tests/*.test.sh; do bash "$t"; done
```

The suite is 780 assertions across ranking, models, providers, panels, power
actions, news feeds, menu parity, and recents. The full build history and
pitfalls log live in [ROADMAP.md](ROADMAP.md). Mutated state stays in
`~/.local/state/omarchy-cmdcenter/`; the plugin never edits
`/usr/share/omarchy/`.

## License

[MIT](LICENSE) (c) 2026 AkinleyeMicheal
