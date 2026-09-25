# Sessions

A summoned overlay that lists the conversations you already have going, grouped by the folder they belong to, and puts you back in the one you pick.

Claude, Grok, Codex and Cursor, newest first. Type to narrow. A chip limits the list to one tool. Enter brings that conversation forward: a terminal already running it is focused, and if there isn't one, your terminal opens resumed in that folder.

The panel keeps a title, the folder and how long ago. The transcript stays in the tool.

- **Plugin ID:** `io.github.kimm-stensborg.sessions`
- **Kind:** `overlay`
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
| Up / Down | Move through the sessions. Headers are skipped. |
| Enter | Focus the terminal already running that session, or open one resumed there. |
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
| `UsageBand.qml` | The subscription rows above the list, and their limits and models when opened. |
| `Model.js` | Titles, grouping, search, the resume command, and which window is already that session. |
| `scan.py` | Reading the four tools' session files, and launching or focusing. |
| `test.js` | `Model.js`. |
| `test_scan.py` | `scan.py`. |
| `install.sh` | The shortcut and enabling the plugin. |

```bash
node test.js
python3 test_scan.py
```
