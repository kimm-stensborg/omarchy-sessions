#!/usr/bin/env node
// Model.js unit tests. The scanner's file reading is covered by test_scan.py.
//
//     node test.js

// Renewal times are shown in local time; pin it so the checks read the same anywhere.
process.env.TZ = "UTC"

const fs = require("fs")
const path = require("path")

function loadModel() {
  const src = fs.readFileSync(path.join(__dirname, "Model.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "")
  const names = []
  for (const m of src.matchAll(/^(?:function|var)\s+([A-Za-z_$][\w$]*)/gm)) names.push(m[1])
  return new Function(src + "\nreturn {" + names.join(", ") + "}")()
}

const M = loadModel()
const HOME = "/home/kimm"
const NOW = Date.parse("2026-09-25T12:00:00Z")
let checks = 0
const failures = []

// A subscription's at-a-glance lines, as the panel reads them.
function lines(panel) {
  return panel.summary.map(l => [l.short, l.text, l.reset].filter(Boolean).join(" "))
}

function check(label, got, want) {
  checks += 1
  const g = JSON.stringify(got)
  const w = JSON.stringify(want)
  if (g !== w) failures.push(label + "\n      got  " + g + "\n      want " + w)
}

check("one line, capped", M.oneLine("  fix\nthe   note  ", 12), "fix the note")
check("one line adds an ellipsis past the cap", M.oneLine("abcdefghijklmnopqrstuvwxyz", 10), "abcdefghi…")

check("toMs accepts iso, millis and seconds", M.toMs("2026-09-25T11:00:00Z"), Date.parse("2026-09-25T11:00:00Z"))
check("toMs treats 10 digits as seconds", M.toMs(1_700_000_000), 1_700_000_000_000)
check("toMs rejects garbage", M.toMs("nope"), 0)

check("project label is the folder, Home for the home directory", M.projectLabel("/home/kimm/Projects/omarchy-notes", HOME), "omarchy-notes")
check("home directory is Home", M.projectLabel("/home/kimm/", HOME), "Home")
check("missing directory is Elsewhere", M.projectLabel("", HOME), "Elsewhere")

const raw = [
  { tool: "claude", id: "c1", cwd: "/home/kimm/Projects/omarchy-notes", updated: NOW - 3600_000, firstUser: "the first line", customTitle: "Overlap" },
  { tool: "claude", id: "c-empty", cwd: "/tmp", updated: NOW, firstUser: "   " },
  { tool: "grok", id: "g1", cwd: "/home/kimm/Projects/casino", updated: "2026-09-25T11:50:00Z", generatedTitle: "Reel timing" },
  { tool: "cursor", id: "u1", cwd: "", fallback: "kvittering", updated: NOW - 86_400_000, firstUser: "where is the receipt" },
  { tool: "codex", id: "x1", cwd: "/home/kimm/Projects/other/notes", updated: NOW - 7200_000, title: "Notes elsewhere" },
  { tool: "", id: "nope", cwd: "/tmp", title: "missing tool" }
]

const sessions = M.normalize(raw, HOME)
check("drops empty titles and incomplete records, newest first", sessions.map(s => s.id), ["g1", "c1", "x1", "u1"])
check("a generated title wins over the first line", sessions[1].title, "Overlap")
check("an auto title stands in for a missing one, and gives way to the tool's", [
  M.titleFrom({ firstUser: "pull", autoTitle: "Repository up to date" }),
  M.titleFrom({ firstUser: "pull", autoTitle: "Repository up to date", aiTitle: "Git pull" }),
  M.titleFrom({ firstUser: "pull", autoTitle: "Repository up to date", customTitle: "Mine" })
], ["Repository up to date", "Git pull", "Mine"])
check("cursor without a directory keeps the fallback name", sessions[3].project, "kvittering")

check("headers follow the newest session in each folder", M.rows(sessions, "", "", NOW, HOME).rows.filter(r => r.kind === "header").map(r => r.project),
  ["casino", "omarchy-notes", "notes", "kvittering"])

const interleaved = M.normalize([
  { tool: "claude", id: "a1", cwd: "/p/arcade", updated: NOW, title: "newest" },
  { tool: "grok", id: "b1", cwd: "/p/bar", updated: NOW - 1, title: "between" },
  { tool: "claude", id: "a2", cwd: "/p/arcade", updated: NOW - 2, title: "older" }
], HOME)
const grouped = M.rows(interleaved, "", "", NOW, HOME).rows
check("a folder gets one header, placed by its newest session", grouped.map(r => r.kind === "header" ? "#" + r.project : r.id),
  ["#arcade", "a1", "a2", "#bar", "b1"])
check("the keyboard order follows the screen", grouped.filter(r => r.kind === "session").map(r => r.cursor), [0, 1, 2])

const sameName = M.normalize([
  { tool: "claude", id: "a", cwd: "/home/kimm/Projects/notes", updated: NOW, title: "One" },
  { tool: "claude", id: "b", cwd: "/home/kimm/Work/notes", updated: NOW - 1, title: "Two" }
], HOME)
check("two folders named notes are told apart", M.rows(sameName, "", "", NOW, HOME).rows.filter(r => r.kind === "header").map(r => r.project),
  ["Projects/notes", "Work/notes"])

const listed = M.rows(sessions, "overlap", "", NOW, HOME)
check("search keeps the matching session under its header", listed.rows.map(r => r.kind === "header" ? r.project : r.id), ["omarchy-notes", "c1"])
check("search counts sessions, not headers", listed.count, 1)
check("tool filter", M.rows(sessions, "", "grok", NOW, HOME).count, 1)
check("every word has to match", M.rows(sessions, "reel missing", "", NOW, HOME).count, 0)
check("the list stops at the cap", M.rows(
  Array.from({ length: 100 }, (_, i) => ({ tool: "claude", id: "s" + i, cwd: "/p/" + i, title: "t", updated: NOW - i })),
  "", "", NOW, HOME).count, M.LIST_LIMIT)

check("ages", [
  M.relativeTime(NOW - 10_000, NOW),
  M.relativeTime(NOW - 5 * 60_000, NOW),
  M.relativeTime(NOW - 3 * 3600_000, NOW),
  M.relativeTime(NOW - 2 * 86_400_000, NOW),
  M.relativeTime(Date.parse("2026-09-01T12:00:00Z"), NOW)
], ["just now", "5m", "3h", "2d", "1 Sep"])

check("resume commands", {
  claude: M.resumeArgv(sessions[1]),
  grok: M.resumeArgv(sessions[0]),
  codex: M.resumeArgv(sessions[2]),
  cursor: M.resumeArgv(sessions[3])
}, {
  claude: ["claude", "--resume", "c1"],
  grok: ["grok", "--cwd", "/home/kimm/Projects/casino", "--resume", "g1"],
  codex: ["codex", "resume", "x1"],
  cursor: ["agent", "--resume", "u1"]
})

const apps = { available: ["herdr", "tmux", "terminal"], default: "herdr", sessions: { c1: "terminal", x1: "zellij" } }
check("a session opens where it was opened last", M.appFor(sessions[1], apps), "terminal")
check("otherwise in the default, and a remembered app that is gone falls back to it",
  [M.appFor(sessions[0], apps), M.appFor(sessions[2], apps)], ["herdr", "herdr"])
check("with nothing installed but a terminal, a terminal", M.appFor(sessions[0], { available: ["terminal"], default: "herdr", sessions: {} }), "terminal")
check("the chooser offers what is installed", M.appChoices(apps).map(a => a.label), ["herdr", "tmux", "Terminal"])
check("open arguments name the folder, the title and the session to remember",
  M.openArgs("herdr", sessions[1], ["claude", "--resume", "c1"], true),
  ["open", "herdr", "/home/kimm/Projects/omarchy-notes", "Overlap", "c1", "claude", "--resume", "c1"])
check("a new conversation is not remembered", M.openArgs("tmux", sessions[1], ["claude"], false)[4], "-")
const inPanes = [{ address: "0x1", text: "herdr\ng1\nc1", panes: [
  { kind: "herdr", pane: "w1:p1", text: "grok\ng1" }, { kind: "tmux", pane: "%3", text: "claude\nc1" }] }]
check("the pane a session runs in says which app it is in", [M.paneKindOf(sessions[0], inPanes), M.paneKindOf(sessions[1], inPanes), M.paneKindOf(sessions[2], inPanes)],
  ["herdr", "tmux", ""])
check("sessions found in panes are remembered when that is news", M.panesToRemember(sessions, inPanes, { sessions: { g1: "herdr" } }), ["c1=tmux"])

const parked = [{ address: "0xa", text: "herdr\nc1\nx1", panes: [{ kind: "herdr", pane: "w9:p1", text: "claude\nc1\nx1" }] }]
check("a background session counts as running even with no window", M.runningIds(sessions, [], ["u1"]), { u1: true })
check("a background session is opened, not focused in the terminal that parked it",
  [M.windowFor(sessions[1], parked, ["c1"]), M.windowFor(sessions[2], parked, ["c1"]).address], [null, "0xa"])
check("a background session is not remembered as living in that pane", M.panesToRemember(sessions, parked, {}, ["c1"]), ["x1=herdr"])

check("a new conversation starts the tool bare", ["claude", "grok", "codex", "cursor", "other"].map(M.newArgv),
  [["claude"], ["grok"], ["codex"], ["agent"], null])

check("a window matches only when the session id is among what runs in it", M.matchClient(sessions[0], [
  { address: "0x1", text: "foot --working-directory=/home/kimm/Projects/casino\ngrok" },
  { address: "0x2", text: "foot\nbash\ngrok\ng1" }
]).address, "0x2")
check("the pane inside the window that runs the session", M.matchPane(sessions[0], {
  address: "0x2", text: "herdr\ngrok\ng1",
  panes: [{ pane: "w1:p1", text: "bash" }, { pane: "w2:p1", tab: "w2:t1", workspace: "w2", text: "grok\ng1" }]
}).pane, "w2:p1")
check("a window without panes has no pane to match", M.matchPane(sessions[0], { address: "0x2", text: "g1" }), null)
check("no id in any window is no match", M.matchClient(sessions[0], [
  { address: "0x1", text: "foot\ngrok" }
]), null)

check("sessions a window is running are marked on their rows", M.rows(sessions, "", "", NOW, HOME,
  M.runningIds(sessions, [{ address: "0x2", text: "foot\ngrok --resume g1" }])).rows
  .filter(r => r.kind === "session").map(r => r.id + (r.running ? "*" : "")), ["g1*", "c1", "x1", "u1"])
check("a header counts the sessions under it", M.rows(interleaved, "", "", NOW, HOME).rows.filter(r => r.kind === "header").map(r => r.count), [2, 1])

check("typed words are marked, case aside, overlaps merged",
  M.highlightHtml("Omarchy Arcade launcher", "arc arcade", "#f00"),
  'Om<font color="#f00">arc</font>hy <font color="#f00">Arcade</font> launcher')
check("every word is marked, and the text is escaped", M.highlightHtml("<b> & notes", "b note", "#f00"),
  '&lt;<font color="#f00">b</font>&gt; &amp; <font color="#f00">note</font>s')
check("no query leaves the text as it was, escaped", M.highlightHtml("a < b", "", "#f00"), "a &lt; b")

const theme = M.themeColors('accent = "#7aa2f7"\norange = "#eb927b"\n# comment\nmagenta="#ad8ee6"\nbad = "nope"')
check("theme colours are read from colors.toml lines", theme, { accent: "#7aa2f7", orange: "#eb927b", magenta: "#ad8ee6" })
check("each tool takes its theme colour, or the fallback", [
  M.toolColor("claude", theme, "#fff"), M.toolColor("grok", theme, "#fff"), M.toolColor("codex", theme, "#fff")
], ["#eb927b", "#ad8ee6", "#fff"])

const chipRow = [{ id: "" }, { id: "claude" }, { id: "grok" }]
check("tab steps through the chips and round", [
  M.nextTool(chipRow, "", 1), M.nextTool(chipRow, "grok", 1), M.nextTool(chipRow, "", -1), M.nextTool(chipRow, "gone", 1)
], ["claude", "", "grok", "claude"])

check("chips follow the tools that actually have sessions", M.toolsPresent(sessions).map(t => t.id), ["claude", "grok", "codex", "cursor"])

check("token counts", [M.formatTokens(999), M.formatTokens(1000), M.formatTokens(38320700), M.formatTokens(1.48e9)],
  ["999", "1K", "38.3M", "1.5B"])
check("model names drop the vendor and join the version", M.friendlyModelName("claude-opus-4-8"), "Opus 4.8")
check("opus 5.5", M.friendlyModelName("claude-opus-5-5"), "Opus 5.5")
check("grok model name", M.friendlyModelName("grok-4.7-build"), "4.7 Build")
check("dollars from ticks", M.formatUsdFromTicks(1.5e10), "$1.50")
check("renewals: countdown inside a day, weekday and time inside a week, date after", [
  M.resetLabel("2026-09-25T12:14:00Z", NOW),
  M.resetLabel("2026-09-25T16:00:00Z", NOW),
  M.resetLabel("2026-09-25T14:14:30Z", NOW),
  M.resetLabel("2026-09-28T08:30:00Z", NOW),
  M.resetLabel("2026-10-09T08:30:00Z", NOW),
  M.resetLabel("2026-09-25T11:00:00Z", NOW),
  M.resetLabel("", NOW)
], ["renews in 14m", "renews in 4h", "renews in 2h 15m", "renews Mon 08:30", "renews 9 Oct", "renews now", ""])

const usage = M.usageFrom([
  {
    id: "claude", name: "Claude", tier: "Max 5x", todayTokens: 38320700,
    limits: [
      { label: "Session (5-hour)", percent: 0.06, resetsAt: "2026-09-25T15:00:00Z" },
      { label: "Weekly (7-day)", percent: 0.29, resetsAt: "2026-10-02T12:00:00Z" }
    ],
    models: [
      { id: "claude-opus-5", input: 10, output: 20, cacheRead: 30, cacheWrite: 40 },
      { id: "claude-opus-5-5", input: 1, output: 2, cacheRead: 300, cacheWrite: 0 }
    ]
  },
  { id: "codex", name: "Codex", tier: "", todayTokens: 0, limits: [], models: [] }
], [
  { models: [{ id: "grok-4.7-build", input: 1000, output: 2000, cacheRead: 0, cacheWrite: 0, costTicks: 1e10 }] },
  { models: [{ id: "grok-4.7-build", input: 500, output: 0, cacheRead: 0, cacheWrite: 0, costTicks: 0.5e10 }] }
], NOW)

check("empty subscriptions drop out, claude stays ahead of grok", usage.map(u => u.id), ["claude", "grok"])
check("claude shows its week above its session, as the other tools lead with theirs", lines(usage[0]),
  ["week 29% renews 2 Oct", "session 6% renews in 3h"])
check("the full view lists the week first too", usage[0].limits.map(l => l.label), ["Weekly (7-day)", "Session (5-hour)"])
check("the heavier model leads and fills the bar", usage[0].models.map(m => [m.name, m.share]), [["Opus 5.5", 1], ["Opus 5", 100 / 303]])
check("grok cost is the sum of the session files", usage[1].todayLabel, "$1.50 · 3.5K")

const week = M.usageFrom([], [
  { models: [{ id: "grok-4.7-build", input: 1000, output: 0, cacheRead: 0, cacheWrite: 0, costTicks: 0 }] }
], NOW, {
  percent: 0.69,
  resetsAt: "2026-09-28T08:30:00Z",
  products: [
    { name: "GrokBuild", percent: 0.67 },
    { name: "GrokChat", percent: 0.02 }
  ]
})[0]
check("grok shows its week; build and chat wait for the full view", lines(week), ["week 69% renews Mon 08:30"])
check("weekly, build and chat are the limit rows", week.limits.map(l => l.label + " " + l.text), ["Weekly 69%", "Build 67%", "Chat 2%"])
check("the meter is the weekly share", week.summary[0].percent, 0.69)

const cursor = M.usageFrom([], [], NOW, null, {
  percent: 7.490909090909091 / 100,
  resetsAt: "2026-09-30T08:54:19Z",
  plan: "Pro",
  products: [
    { name: "Auto", percent: 6.626666666666667 / 100 },
    { name: "API", percent: 16.133333333333333 / 100 }
  ],
  onDemand: "off"
})[0]
check("cursor shows the included share of the monthly plan", [cursor.tier, lines(cursor)], ["Pro", ["included 7% renews Wed 08:54"]])
check("auto, api and on-demand follow the included row", cursor.limits.map(l => l.label + " " + l.text),
  ["Included 7%", "Auto 7%", "API 16%", "On-Demand Disabled"])
check("a plan past its allowance reads past 100%, not near zero", M.usageFrom([], [], NOW, null, {
  percent: 1.2, resetsAt: "", plan: "Pro", products: [], onDemand: "on"
})[0].summary[0].text, "120%")
check("three quarters used is a warning, not yet an alarm", M.usageFrom([{
  id: "claude", name: "Claude", todayTokens: 0,
  limits: [{ label: "Weekly", percent: 0.8, resetsAt: "" }], models: []
}], [], NOW)[0].summary.map(l => [l.warning, l.alarming]), [[true, false]])
check("a limit near full is marked", M.usageFrom([{
  id: "claude", name: "Claude", todayTokens: 0,
  limits: [{ label: "Weekly", percent: 0.94, resetsAt: "" }], models: []
}], [], NOW)[0].summary[0].alarming, true)
check("with no renewal anywhere the first limit stands in", lines(M.usageFrom([{
  id: "codex", name: "Codex", todayTokens: 0,
  limits: [{ label: "Weekly", percent: 0.4, resetsAt: "" }, { label: "Daily", percent: 0.1, resetsAt: "" }], models: []
}], [], NOW)[0]), ["week 40%"])
check("grok with only this machine's numbers has no allowance lines", M.usageFrom([], [
  { models: [{ id: "grok-4.7-build", input: 1000, output: 0, cacheRead: 0, cacheWrite: 0, costTicks: 0 }] }
], NOW)[0].summary, [])

const bar = M.barSummary(M.usageFrom([{
  id: "claude", name: "Claude Code", todayTokens: 0, models: [],
  limits: [
    { label: "Session (5-hour)", percent: 0.28, resetsAt: "2026-09-25T13:20:00Z" },
    { label: "Weekly (7-day)", percent: 0.32, resetsAt: "2026-09-27T03:00:00Z" }
  ]
}], [], NOW, { percent: 0.79, resetsAt: "2026-09-28T08:30:00Z", products: [] }))
check("the bar shows the fullest allowance of any subscription", [bar.tool, bar.text, bar.warning, bar.alarming], ["grok", "79%", true, false])
check("the switch names each tool with its fullest share", M.usageFrom([{
  id: "claude", name: "Claude Code", todayTokens: 0, models: [],
  limits: [
    { label: "Session (5-hour)", percent: 0.47, resetsAt: "2026-09-25T14:00:00Z" },
    { label: "Weekly (7-day)", percent: 0.34, resetsAt: "2026-09-27T03:00:00Z" }
  ]
}], [], NOW).map(M.switchLabel), ["Claude 47%"])
check("no allowances leaves the bar empty", M.barSummary([]), null)
const both = M.usageFrom([{
  id: "claude", name: "Claude Code", todayTokens: 0, models: [],
  limits: [{ label: "Weekly (7-day)", percent: 0.32, resetsAt: "2026-09-27T03:00:00Z" }]
}], [], NOW, { percent: 0.79, resetsAt: "2026-09-28T08:30:00Z", products: [] })
check("the bar can be set to one tool", [M.barSummary(both, "claude").tool, M.barSummary(both, "claude").text], ["claude", "32%"])
check("a tool with nothing to show falls back to the fullest", M.barSummary(both, "cursor").tool, "grok")
check("the choices are fullest and each tool with an allowance", M.barChoices(both).map(c => c.id), ["fullest", "claude", "grok"])

const week7 = M.dayRows([
  { date: "2026-09-25", tokens: 1000 }, { date: "2026-09-23", tokens: 400 }, { date: "2026-09-23", tokens: 100 },
  { date: "2026-09-10", tokens: 9999 }
], NOW)
check("seven days, oldest first, ending today", week7.map(d => d.day), ["Sat", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri"])
check("a day's records add up and scale to the busiest day", week7.map(d => [d.label, d.share, d.today]).slice(4),
  [["500", 0.5, false], ["", 0, false], ["1K", 1, true]])
check("no tokens in the week is no chart", M.dayRows([{ date: "2026-09-10", tokens: 5 }], NOW), [])
check("today's prompts and sessions", M.activityLabel(410, 1), "410 prompts · 1 session")
check("grok's days come from its session files", M.usageFrom([], [
  { day: "2026-09-25", models: [{ id: "grok-4.7-build", input: 1000, output: 500, cacheRead: 0, cacheWrite: 0 }] }
], NOW)[0].days.slice(-1)[0].label, "1.5K")

const spots = [
  { tool: "claude", id: "a", cwd: "/home/kimm/Projects/casino", key: "/home/kimm/Projects/casino", title: "x", updated: 5, project: "casino" },
  { tool: "codex", id: "b", cwd: "/work/casino", key: "/work/casino", title: "y", updated: 4, project: "casino" },
  { tool: "grok", id: "c", cwd: "/home/kimm/Projects/casino", key: "/home/kimm/Projects/casino", title: "z", updated: 3, project: "casino" },
  { tool: "claude", id: "d", cwd: "/home/kimm", key: "/home/kimm", title: "w", updated: 2, project: "Home" },
  { tool: "claude", id: "e", cwd: "", key: "e", title: "v", updated: 1, project: "Elsewhere" }
]
const places = M.workspaces(spots, HOME)
check("workspaces: each folder once, newest first, named like the headers", places.map(w => [w.label, w.path, w.count, w.tools]),
  [["Projects/casino", "~/Projects/casino", 2, ["claude", "grok"]], ["work/casino", "/work/casino", 1, ["codex"]], ["Home", "~", 1, ["claude"]]])
check("workspaces filter on name and path, every word", M.filterWorkspaces(places, "cas proj").map(w => w.cwd), ["/home/kimm/Projects/casino"])
check("an empty filter keeps them all", M.filterWorkspaces(places, " ").length, 3)
check("a workspace is found by folder", [M.workspaceIndex(places, "/work/casino"), M.workspaceIndex(places, "/nope")], [1, -1])
check("rows narrowed to one folder", M.rows(spots, "", "", NOW, HOME, {}, "/home/kimm/Projects/casino").rows.filter(r => r.kind === "session").map(r => r.id), ["a", "c"])
check("new sessions start with the installed tools", M.newTools({ tools: ["cursor", "claude"] }, spots).map(t => t.id), ["claude", "cursor"])
check("without that, with the tools that have sessions", M.newTools({}, spots).map(t => t.id), ["claude", "grok", "codex"])

if (failures.length) {
  console.log(failures.join("\n"))
  console.log(failures.length + " failed, " + (checks - failures.length) + " ok")
  process.exit(1)
}
console.log(checks + " ok")
