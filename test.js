#!/usr/bin/env node
// Model.js unit tests. The scanner's file reading is covered by test_scan.py.
//
//     node test.js

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

check("a window matches only when the session id is among what runs in it", M.matchClient(sessions[0], [
  { address: "0x1", text: "foot --working-directory=/home/kimm/Projects/casino\ngrok" },
  { address: "0x2", text: "foot\nbash\ngrok\ng1" }
]).address, "0x2")
check("no id in any window is no match", M.matchClient(sessions[0], [
  { address: "0x1", text: "foot\ngrok" }
]), null)

check("chips follow the tools that actually have sessions", M.toolsPresent(sessions).map(t => t.id), ["claude", "grok", "codex", "cursor"])

check("token counts", [M.formatTokens(999), M.formatTokens(1000), M.formatTokens(38320700), M.formatTokens(1.48e9)],
  ["999", "1K", "38.3M", "1.5B"])
check("model names drop the vendor and join the version", M.friendlyModelName("claude-opus-4-8"), "Opus 4.8")
check("opus 5.5", M.friendlyModelName("claude-opus-5-5"), "Opus 5.5")
check("grok model name", M.friendlyModelName("grok-4.7-build"), "4.7 Build")
check("dollars from ticks", M.formatUsdFromTicks(1.5e10), "$1.50")
check("a reset a few hours out", M.resetLabel("2026-09-25T16:00:00Z", NOW), "resets 4h")

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
check("claude headline is the allowances", usage[0].headline, "session 6% · week 29%")
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
check("the grok row leads with the weekly allowance", week.headline, "week 69%")
check("weekly, build and chat are the limit rows", week.limits.map(l => l.label + " " + l.text), ["Weekly 69%", "Build 67%", "Chat 2%"])
check("the meter is the weekly share", week.meter, 0.69)

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
check("cursor leads with the included share of the monthly plan", [cursor.tier, cursor.headline], ["Pro", "included 7%"])
check("auto, api and on-demand follow the included row", cursor.limits.map(l => l.label + " " + l.text),
  ["Included 7%", "Auto 7%", "API 16%", "On-Demand Disabled"])
check("a plan past its allowance reads past 100%, not near zero", M.usageFrom([], [], NOW, null, {
  percent: 1.2, resetsAt: "", plan: "Pro", products: [], onDemand: "on"
})[0].headline, "included 120%")
check("a limit near full is marked", M.usageFrom([{
  id: "claude", name: "Claude", todayTokens: 0,
  limits: [{ label: "Weekly", percent: 0.94, resetsAt: "" }], models: []
}], [], NOW)[0].alarming, true)

if (failures.length) {
  console.log(failures.join("\n"))
  console.log(failures.length + " failed, " + (checks - failures.length) + " ok")
  process.exit(1)
}
console.log(checks + " ok")
