# Sessions

A summoned overlay that lists the conversations you already have going, grouped by the folder they belong to, and puts you back in the one you pick.

Claude, Grok, Codex and Cursor, newest first. Type to narrow. A chip limits the list to one tool. Enter brings that conversation forward: a terminal already running it is focused, and if there isn't one, your terminal opens resumed in that folder.

The panel keeps a title, the folder and how long ago. The transcript stays in the tool.

Each folder gets a header with how many sessions are under it. A dot in front of a session means a window is already running it, so Enter will bring that window forward rather than open another. Each tool has its own colour, taken from the theme, on its chip and beside its name in the list. While you type, the words that matched light up in titles and folder names. An allowance turns amber at three quarters used and red at 90%.

A session counts as already running in a window when its id turns up anywhere inside that window: on the command line of the terminal or of anything started in it, including panes of a multiplexer, in a file one of those processes has open, or in what the tool records for that process. Claude writes one to `~/.claude/sessions/<pid>.json` and Grok to `~/.grok/active_sessions.json`. Cursor's `agent` names its conversation in the log it keeps open. Codex is recognized when it was started with `codex resume <id>`. A terminal running as a server, one process behind several windows, can't be told apart per window, so only its own command line counts. When the session runs in a [herdr](https://herdr.dev) pane, that pane is brought forward too, not just the window holding it.

- **Plugin ID:** `io.github.kimm-stensborg.sessions`
- **Kinds:** `overlay`, `bar-widget`
- **License:** MIT
- **Requires:** Omarchy 4 (Quattro) with `omarchy-shell`

## What it shows

The recent sessions on this machine, not the whole history: up to forty Claude transcripts, forty Grok sessions, thirty Codex threads and thirty Cursor chats. A session with no title and nothing you typed is left out.

| Tool | Read from | Resumed with |
|------|-----------|--------------|
| Claude | `~/.claude/projects/<project>/*.jsonl` | `claude --resume <id>` |
| Grok | `~/.grok/sessions/<cwd>/<id>/summary.json` | `grok --cwd <dir> --resume <id>` |
| Codex | `~/.codex/state_*.sqlite` | `codex resume <id>` |
| Cursor | `~/.cursor/projects/<project>/agent-transcripts/` | `agent --resume <id>` |

A generated title is shown when the tool wrote one. Otherwise the first line you typed. Claude and Cursor name the project folder by replacing slashes, and that name is turned back into a real path by matching it against directories that exist, so `omarchy-notes` stays one folder. Claude's own record of the directory wins when the transcript has one.

Above the list, each subscription that has numbers gets a column, side by side. Claude, Codex and Fireworks use the usage records Omarchy already writes for its agents panel: the allowance used, when it renews, today's tokens, and the per-model split. Click it, or the tool's chip, and its allowances and that split open in full. Grok's column is the weekly allowance from the same billing figure `/usage` shows, and under it the Build and Chat shares of that week. The model lines under Grok stay the sum of the session files on this machine. Cursor's column is the monthly plan from the same screen as `agent` `/usage`: the included percent, Auto and API inside it, and whether on-demand is on. A subscription with nothing recorded yet is left off the strip. Each allowance that renews gets its own line and meter, with when it renews: a countdown inside a day, the weekday and time inside a week, the date after that. Claude shows its week and, under it, its 5-hour session that way, so every column opens on its longest allowance. Shares inside an allowance, like Grok's Build and Chat or Cursor's Auto and API, wait for the full view.

## In the bar

The bar widget takes the place of Omarchy's Agents widget: every AI subscription's usage in one bar button and one popup. The button wears the Agents glyph and the share used, amber from 75% and red from 90%. By default that is whichever allowance is closest to its limit; **In the bar**, at the foot of the popup, steps to one tool instead (the `barTool` setting: `fullest`, `claude`, `grok`, `codex`, `cursor` or `fireworks`). Hover it for every allowance and when it renews.

Left click opens the popup, laid out as the Agents panel is and one tool at a time: its mark, plan and today's prompts and sessions, then its limits and when each renews, its tokens for each of the last seven days, and its tokens by model. Middle click opens the Sessions search. In the popup, `h` / `l` or the arrows switch tool, `b` changes what the bar shows, `r` refreshes, `s` opens Sessions, Esc closes. A key can open it too:

```bash
omarchy-shell io.github.kimm-stensborg.sessions.usage toggle
```

Enabling the plugin puts the button on the bar. Take Agents off it with `omarchy plugin disable omarchy.agents`; Sessions runs Omarchy's collector (`omarchy-agent-usage-update`) itself, so the Claude, Codex and Fireworks numbers keep coming. Everything is read from a cache at `~/.cache/omarchy/sessions/usage.json`, which the bars refresh every five minutes and the Sessions panel whenever it opens, so every monitor and the panel agree and Grok and Cursor are asked once however many bars there are. Cross-machine syncing, which Agents offers, is not carried over.

Opening the panel asks `cli-chat-proxy.grok.com` for Grok's weekly figure, using the sign-in in `~/.grok/auth.json`, and `api2.cursor.sh` for Cursor's, using `~/.config/cursor/auth.json`. If the Grok request fails, the newest `billing: fetched credits config` line in `~/.grok/logs/unified.jsonl` is used instead.

## Install

```bash
omarchy plugin add https://github.com/kimm-stensborg/omarchy-sessions.git
~/.config/omarchy/plugins/io.github.kimm-stensborg.sessions/install.sh
```

Plugins land disabled so the code can be read before it runs — they execute unsandboxed inside `omarchy-shell`. `install.sh` proposes a shortcut, binds the one you accept, and then enables the plugin.

It proposes `SUPER + ALT + S`, or the first free fallback if Hyprland already has that one. The binding lands in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + ALT + S", "Sessions", "omarchy-shell shell toggle io.github.kimm-stensborg.sessions '{}'")
```

`toggle` rather than `summon`, so the same key closes it. Re-running the script replaces its own block rather than stacking a second one.

```bash
install.sh --key "SUPER + SHIFT + J"   # skip the prompt
install.sh --no-bind                   # just enable the plugin
```

Or summon it directly:

```bash
omarchy-shell shell toggle io.github.kimm-stensborg.sessions '{}'
omarchy-shell shell summon io.github.kimm-stensborg.sessions '{"query":"notes","tool":"claude"}'
```

## Keys

| Key | Does |
|-----|------|
| Type | Narrows the list. Every word has to match the title, the folder or the tool. |
| Up / Down | Move from the newest session towards the oldest and back. It stops at either end rather than wrapping round. Headers are skipped. |
| Enter | Focus the terminal already running that session, or open one resumed there. |
| Ctrl+Enter | Start a new conversation with that session's tool, in its folder. |
| Tab / Shift+Tab | Step to the next or previous chip: All, then each tool, and round again. |
| Click a chip | Show only that tool, and its allowance and models when those exist. Click it again for all of them. |
| Click a subscription | Same as its chip. |
| Esc | Clear the line, or close the panel when the line is empty. |

## Dependencies

| Package | Used for |
|---------|----------|
| `python` | `scan.py`, which reads the session files and opens a terminal |
| `hyprctl` | seeing which windows are already running a session, and focusing one |
| `xdg-terminal-exec`, `uwsm` | launching the resume command in the session's own scope |
| `jq` | `install.sh`, when it checks which shortcuts are free |

Grok's weekly figure and Cursor's monthly plan are fetched when the panel opens. Everything else is read from disk. `claude`, `grok`, `codex` and `agent` are only needed for the tools you actually resume.

## Remove

```bash
omarchy plugin remove io.github.kimm-stensborg.sessions
```

Then delete the `-- Sessions overlay` block from `~/.config/hypr/bindings.lua`.

## Files

| File | Owns |
|------|------|
| `Sessions.qml` | The panel: search line, chips and the session list. |
| `BarWidget.qml` | The bar button, its setting and tooltip, the five-minute refresh, and the popup's key. |
| `UsagePanel.qml` | The popup under the bar button. |
| `UsageBand.qml` | The subscriptions side by side, and one opened in full: limits, the last seven days, models. |
| `Model.js` | Titles, grouping, search, the resume command, and which window is already that session. |
| `scan.py` | Reading the four tools' session files, the usage cache, and launching or focusing, herdr panes included. |
| `test.js` | `Model.js`. |
| `test_scan.py` | `scan.py`. |
| `install.sh` | The shortcut and enabling the plugin. |

```bash
node test.js
python3 test_scan.py
```
