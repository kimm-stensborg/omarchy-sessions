# Sessions

A summoned overlay that lists the conversations you already have going, grouped by the folder they belong to, and puts you back in the one you pick.

Claude, Grok, Codex and Cursor, newest first. Type to narrow. Three pills under the search line narrow it further: to one tool, to what is running, to one workspace. Enter brings that conversation forward: a terminal already running it is focused, and if there isn't one, your terminal opens resumed in that folder.

The panel keeps a title, the folder and how long ago. The transcript stays in the tool.

Each folder gets a header with how many sessions are under it. A dot in front of a session means a window is already running it, so Enter will bring that window forward rather than open another. A running agent also says how it is doing where the time would be: **working…** while it works (its dot breathes), **your turn** when it has finished, and **needs you**, in amber, when it is waiting on an answer such as a permission. Claude says so in its own record per process; herdr says it for any agent in its panes. The panel asks again every three seconds while it is open, so the words change in place. Each tool has its own colour, taken from the theme, on the tool pill and beside its name in the list. While you type, the words that matched light up in titles and folder names. An allowance turns amber at three quarters used and red at 90%.

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

A session shows, in this order: a name you gave it, the title the tool generated (Cursor's comes from its chat's `meta.json`, skipping its "New Agent" placeholder), a title generated for it here, and only then the first line you typed. Claude and Cursor name the project folder by replacing slashes, and that name is turned back into a real path by matching it against directories that exist, so `omarchy-notes` stays one folder. The tool's own record of the directory wins when it has one.

**Naming sessions.** F2 names the session in hand; an empty name gives it back its own title. A Claude session gets the same record Claude's `/rename` writes, so Claude's `/resume` shows the name too. Grok, Codex and Cursor have nowhere to put one, so their names are kept in `~/.local/state/omarchy/sessions/titles.json`.

**Titles for untitled sessions.** Some sessions never get a title from their tool; Claude only titles a conversation once it gets going, so a one-prompt session like "pull" has none. When the panel finds such sessions it asks Claude's Haiku, through the `claude` CLI already signed in, for a short title from each one's first prompt and first answer: once, for all of them together, in the background, with no tools and no session saved. The titles are kept in the same `titles.json`, so each session is only named once. This sends those first lines to Anthropic and uses a little of your Claude allowance; without the `claude` CLI signed in, nothing is sent and the first prompt stays.

At the foot of the panel, a strip of fixed height gives each subscription that has numbers a column, side by side, whichever tool is picked above; the list never moves as the numbers come in. Claude, Codex and Fireworks use the usage records Omarchy writes. Grok's column is the weekly allowance from the same billing figure `/usage` shows, and Cursor's the monthly plan from the same screen as `agent` `/usage`. A subscription with nothing recorded yet is left off the strip. Each allowance that renews gets its own line and meter, with when it renews: a countdown inside a day, the weekday and time inside a week, the date after that. Claude shows its week and, under it, its 5-hour session, so every column opens on its longest allowance. Clicking a column shows only that tool's sessions. Shares inside an allowance (Grok's Build and Chat, Cursor's Auto and API), the last seven days and the split by model are in the bar's popup, described below.

## Starting a session

Ctrl+Enter asks for a tool and a workspace, then starts a new conversation there in the default app. It starts on the tool and folder of the session in hand; the tools offered are the installed ones (`claude`, `grok`, `codex`, and `agent` for Cursor). The workspaces are every folder a session was held in, newest first, with a dot for each tool used there. Typing narrows them by name and path, every word has to match; the arrows move through them, ←/→ or Tab switch tool, Enter starts, and Esc clears what was typed, then cancels. A workspace that isn't there yet is made by typing it: what was typed is offered last as "+ new", a plain name in the folder most of your workspaces sit in (typically `~/Projects`), a path starting with `~` or `/` as it is. Its folder is made when the session starts, and herdr gives it a workspace of its own.

## The pills

Three pills under the search line narrow the list, and each says what it shows. Tab walks them from left to right and back to the list (Shift+Tab the other way); Enter on the one in hand opens or switches it, and Esc goes back to the list. They combine with each other and with typing.

- **Tools**: "All tools" to begin with. Enter, a click or Ctrl+T drops the list of tools that have sessions; pick one and only its sessions show, with its colour on the pill. Clicking a subscription at the foot of the panel shows that tool too.
- **Running**: only the sessions already running, those with a dot, background sessions included. Enter, a click or Ctrl+R switches it.
- **Workspaces**, at the right: "All workspaces" to begin with. Enter, a click or Ctrl+W opens the same list as for a new session, to pick one: only its sessions show, and the pill names it, with a × to let go. Clicking a folder's header does the same, and clicking it again lets go; so does "All workspaces" at the top of the list.

The tool, workspace and running filters are kept between launches, in `~/.local/state/omarchy/sessions/filters.json`, and come back the next time the panel opens.

## Where sessions open

A session that is not running opens in **herdr**, **tmux** or a plain **Terminal**; only the installed ones are offered. It opens where it was opened last, and otherwise in the default, which is herdr when it is installed. Shift+Enter asks instead: pick an app with the arrows or Tab and Enter, and that session opens there from then on; `d` makes the highlighted one the default.

- **herdr**: a new tab in the workspace named after the session's folder (herdr names its workspaces after folders), or a new workspace when there is none. The window holding herdr comes forward; with none open, a terminal running `herdr` is started first.
- **tmux**: a new window in the tmux session a terminal is attached to, which then comes forward; with no tmux client attached, a new terminal with a new tmux session.
- **Terminal**: a new window of your default terminal, as `xdg-terminal-exec` picks it.

A Claude session running in the background (one Claude parked as a background job) counts as running but has no window of its own: Enter opens it with `claude attach` in its app, as Claude requires, rather than `--resume`, which Claude refuses for a running session. A session found running in a herdr or tmux pane is remembered there as well, so one started by hand opens there again next time. Sessions in tmux are brought forward in their pane, as herdr's are. Both are found through the terminal showing them, so a herdr server that has outlived the terminal that started it still counts. What is remembered lives in `~/.local/state/omarchy/sessions/apps.json`.

## Peeking and pinning

→ opens a pane beside the list with the last few things said in the session in hand: what you wrote and what the agent answered, without tool calls, newest at the bottom. It follows the selection as you move, and ← hides it. Only the tail of the transcript is read, so a long session opens as fast as a short one; a session whose last stretch is all tool work shows only the agent's words.

Ctrl+P pins the session in hand: it moves to a **Pinned** group at the top of the list, with its folder named beside it, and stays there between launches. Ctrl+P on it again puts it back in its folder. Pins live in `~/.local/state/omarchy/sessions/pins.json`.

## Deleting a session

Del on a session asks first, naming it; Del or Enter deletes, Esc keeps it. A session that is still running cannot be deleted: the panel will not offer it, and before deleting `scan.py` looks again across every process on the machine, not only the ones in a window, so a session in a background pane or job is safe too. A session another one was forked from (Claude's `--fork-session`, as a background session does) is not counted as running just because the fork started from it.

A Claude session running in the background has no window to close it in, and its row says **background**. Del on it offers to stop it instead (`claude stop`), which keeps the conversation; once it has stopped, Del deletes it as any other.

A deleted session folds out of the list and the one above it is selected. The list stays scrolled where it was, so the selection keeps its place on screen and nothing slides under it before the next Del.

| Tool | What goes |
|------|-----------|
| Claude | the transcript, its subagent folder, and its file history, session environment and todos, to the trash |
| Grok | the session's folder under `~/.grok/sessions`, to the trash |
| Cursor | the transcript and the chat `agent --resume` reopens (`~/.config/cursor/chats`), to the trash |
| Codex | through Codex's own `codex delete`, which is permanent |

Only files named by the session's exact id, under that tool's own folders, are touched. Something deleted by mistake can be restored from the trash.

## In the bar

The bar widget takes the place of Omarchy's Agents widget: every AI subscription's usage in one bar button and one popup. The button wears the Agents glyph and the share used, both amber from 75% and red from 90%. By default that is whichever allowance is closest to its limit; **In the bar**, at the foot of the popup, steps to one tool instead (the `barTool` setting: `fullest`, `claude`, `grok`, `codex`, `cursor` or `fireworks`).

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
| Enter | Focus the terminal already running that session, or open it resumed where it was opened last (herdr, tmux or a terminal), else in the default. |
| Shift+Enter | Choose where it opens: herdr, tmux or Terminal. The choice is remembered for that session; `d` in the chooser makes it the default. |
| Ctrl+Enter | Start a new conversation: pick the tool and the workspace, those of the session in hand to start with, or type a new workspace's name. It opens in the default app. |
| Ctrl+W | Show only one workspace's sessions, picked from a list you can type to narrow. Same as clicking the workspace pill. |
| Ctrl+R | Show only the running sessions, or all of them again. Same as the Running pill. |
| Ctrl+T | Pick the tool whose sessions show, or all tools. Same as the tool pill. |
| → / ← | Show the last messages of that session beside the list, or hide them. |
| Ctrl+P | Pin that session to the top of the list, or unpin it. |
| F2 | Name that session. Enter saves, Esc cancels; an empty name gives it back its own title. |
| Del | Delete that session, after asking. Del or Enter deletes, Esc cancels. A session still running anywhere can't be deleted; one running in the background is offered a stop instead. |
| Tab / Shift+Tab | Move along the pills (tools, running, workspace) and back to the list. Enter opens or switches the one in hand, Esc goes back to the list. |
| Click a subscription at the foot | Show only that tool's sessions. |
| Click a folder header | Show only that folder's sessions. Click it again for all of them. |
| Esc | Clear the line, or close the panel when the line is empty. The filters stay. |
| Ctrl+? (or F1) | Every shortcut on one sheet. The foot of the panel shows only the few for the session in hand. |

## Dependencies

| Package | Used for |
|---------|----------|
| `python` | `scan.py`, which reads the session files and opens a terminal |
| `hyprctl` | seeing which windows are already running a session, and focusing one |
| `xdg-terminal-exec`, `uwsm` | launching the resume command in the session's own scope |
| `jq` | `install.sh`, when it checks which shortcuts are free |
| `gio` (glib2) | moving a deleted session to the trash |
| `herdr`, `tmux` | optional: opening sessions in them, and finding sessions running in their panes |
| `claude` | optional: titles for sessions no tool has named |

Grok's weekly figure and Cursor's monthly plan are fetched when the panel opens. Everything else is read from disk. `claude`, `grok`, `codex` and `agent` are only needed for the tools you actually resume.

## Remove

```bash
omarchy plugin remove io.github.kimm-stensborg.sessions
```

Then delete the `-- Sessions overlay` block from `~/.config/hypr/bindings.lua`.

## Files

| File | Owns |
|------|------|
| `Sessions.qml` | The panel: search line, pills and the session list. |
| `ToolMenu.qml` | The tool pill's list of tools. |
| `PeekPane.qml` | The → pane: the last messages of the session in hand. |
| `BarWidget.qml` | The bar button, its setting, the five-minute refresh, and the popup's key. |
| `UsagePanel.qml` | The popup under the bar button. |
| `RenameDialog.qml` | The F2 dialog: naming a session. |
| `ShortcutsSheet.qml` | The Ctrl+? sheet: every key, in groups. |
| `WorkspacePicker.qml` | The Ctrl+Enter and Ctrl+W dialog: a tool and a workspace for a new session, or the workspace to show. |
| `AppChooser.qml` | The Shift+Enter chooser: which app a session opens in. |
| `UsageBand.qml` | The fixed-height strip of subscriptions at the foot of the Sessions panel. |
| `Model.js` | Titles, grouping, search, the resume command, and which window is already that session. |
| `scan.py` | Reading the four tools' session files, the usage cache, launching or focusing (herdr panes included), and deleting. |
| `test.js` | `Model.js`. |
| `test_scan.py` | `scan.py`. |
| `install.sh` | The shortcut and enabling the plugin. |

```bash
node test.js
python3 test_scan.py
```
