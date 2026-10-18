# Command Center

A Raycast-style launcher for [Omarchy](https://omarchy.org) — one palette in
front of every command, app, and system control your desktop exposes.

Summon it with **Super+Shift+K**, click its ⚙ button in the bar, or run
`omarchy-shell shell toggle fonsgaudii.cmdcenter '{}'`.

## What it does

- **Search everything** — every `omarchy` command and installed app, ranked
  by usage and recency, with images wherever apps and media appear.
- **Universal providers** — calculator, unit conversion, web search,
  ask-an-agent, window switcher, clipboard history, files, dictionary.
- **Groups sidebar** — All commands · Pinned · Apps · **Controls** (live
  status readouts + curated quick actions) · **History** (launch timeline
  with a fixed recents strip) · **News** (RSS, edit feeds in `$EDITOR`).
- **Home tiles** — a minimalist System & Network tile (real-time ping, packet
  loss, throughput, IP, gateway, CPU) and Weather · Today for a real
  location. The dashboard never refreshes on a timer; the network tile ticks
  only while the palette is open.
- **Power & session** — sleep/lock/logout/shutdown with confirmation on the
  destructive ones.
- **Super+Space parity** — everything Omarchy's menu exposes is in here, and
  `tests/parity.test.js` byte-matches our action strings against
  `omarchy-menu.jsonc` so an Omarchy update can't silently drift us.
- **Bar widget** — a one-slot launcher beside the Omarchy menu (left click
  opens the palette, right click opens a terminal).

## Install

```sh
omarchy plugin add https://github.com/AkinleyeMicheal/omarchy-command-center.git --enable
omarchy bar put fonsgaudii.cmdcenter --after omarchy.menu   # optional bar button
```

## Uninstall

```sh
omarchy plugin remove fonsgaudii.cmdcenter
```

## Development

```sh
omarchy plugin validate .        # manifest schema
omarchy restart shell            # QML errors only surface on restart
for t in tests/*.test.js; do node "$t"; done
for t in tests/*.test.sh; do bash "$t"; done
```

The suite is 772 assertions across the ranking, models, providers, panels,
power actions, news feeds, and menu-parity layers.

Mutated state lives only in `~/.local/state/omarchy-cmdcenter/`; the plugin
never edits `/usr/share/omarchy/`. The full build history and pitfalls log
are in [ROADMAP.md](ROADMAP.md).
