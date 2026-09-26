.pragma library

// Pure logic for Sessions: turn the small records the scanner found into
// the list on screen, and decide what "open this one" means. Nothing here
// touches a file or a window, so `node test.js` covers it.

var TOOLS = ["claude", "grok", "codex", "cursor"]
var TITLE_LIMIT = 90
var LIST_LIMIT = 80

var DAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

function str(v) {
  return v === undefined || v === null ? "" : String(v)
}

function oneLine(v, limit) {
  var text = str(v).replace(/\s+/g, " ").trim()
  var cap = limit || TITLE_LIMIT
  if (text.length <= cap) return text
  return text.slice(0, cap - 1).trim() + "…"
}

// A timestamp from any of the tools, as milliseconds. Seconds and digit
// strings are accepted; anything else is "unknown" and sorts last.
function toMs(v) {
  if (typeof v === "number" && isFinite(v)) return v < 1e12 ? Math.round(v * 1000) : Math.round(v)
  var text = str(v).trim()
  if (!text) return 0
  if (/^\d+$/.test(text)) return toMs(Number(text))
  var parsed = Date.parse(text)
  return isFinite(parsed) ? parsed : 0
}

function cleanPath(cwd) {
  var path = str(cwd).trim()
  if (path.length > 1) path = path.replace(/\/+$/, "")
  return path
}

function projectLabel(cwd, home) {
  var path = cleanPath(cwd)
  var homePath = cleanPath(home)
  if (!path) return "Elsewhere"
  if (path === "/" || (homePath && path === homePath)) return "Home"
  var parts = path.split("/")
  return parts[parts.length - 1] || "Elsewhere"
}

function toolLabel(tool) {
  if (tool === "claude") return "Claude"
  if (tool === "grok") return "Grok"
  if (tool === "codex") return "Codex"
  if (tool === "cursor") return "Cursor"
  return str(tool)
}

// Each tool wears one of the theme's named colours, so a mixed list scans by
// colour and a theme switch recolours it with everything else.
var TOOL_COLORS = { claude: "orange", grok: "magenta", codex: "green", cursor: "cyan" }

// `name = "#rrggbb"` lines from a theme's colors.toml, as { name: "#rrggbb" }.
function themeColors(raw) {
  var colors = {}
  var lines = str(raw).split("\n")
  for (var i = 0; i < lines.length; i++) {
    var match = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})\b/)
    if (match) colors[match[1]] = match[2]
  }
  return colors
}

function toolColor(tool, colors, fallback) {
  var name = TOOL_COLORS[tool]
  return (name && colors && colors[name]) || fallback
}

function escapeHtml(text) {
  return str(text).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;")
}

// `text` as styled text with every typed word in `color`, so it is plain
// why a row matched. Overlapping words merge into one run.
function highlightHtml(text, query, color) {
  var source = str(text)
  var words = str(query).trim().toLowerCase().split(/\s+/).filter(function(w) { return w })
  if (!words.length) return escapeHtml(source)
  var lower = source.toLowerCase()
  var marked = []
  for (var w = 0; w < words.length; w++) {
    for (var at = lower.indexOf(words[w]); at !== -1; at = lower.indexOf(words[w], at + 1)) {
      for (var k = at; k < at + words[w].length; k++) marked[k] = true
    }
  }
  var out = ""
  var open = false
  for (var i = 0; i < source.length; i++) {
    if (marked[i] && !open) { out += '<font color="' + color + '">'; open = true }
    if (!marked[i] && open) { out += "</font>"; open = false }
    out += escapeHtml(source.charAt(i))
  }
  if (open) out += "</font>"
  return out
}

// The title worth showing, in the order a person would recognize it: a
// name you gave it, then the tool's own, and only then the first line that
// was typed.
function titleFrom(raw) {
  return oneLine(raw.customTitle) || oneLine(raw.aiTitle) || oneLine(raw.summary)
    || oneLine(raw.generatedTitle) || oneLine(raw.title) || oneLine(raw.firstUser)
}

function sessionFromRaw(raw, home) {
  if (!raw || typeof raw !== "object") return null
  var tool = str(raw.tool).trim()
  var id = str(raw.id).trim()
  if (!tool || !id) return null
  var title = titleFrom(raw)
  if (!title) return null
  var cwd = cleanPath(raw.cwd)
  var key = cwd || str(raw.fallback).trim() || id
  return {
    tool: tool,
    id: id,
    cwd: cwd,
    key: key,
    title: title,
    updated: toMs(raw.updated),
    project: projectLabel(cwd || str(raw.fallback), home)
  }
}

function normalize(rawList, home) {
  var out = []
  var list = rawList || []
  for (var i = 0; i < list.length; i++) {
    var session = sessionFromRaw(list[i], home)
    if (session) out.push(session)
  }
  out.sort(function(a, b) {
    if (b.updated !== a.updated) return b.updated - a.updated
    if (a.title < b.title) return -1
    if (a.title > b.title) return 1
    return 0
  })
  return out
}

// Two folders with the same name would otherwise share a header. The
// parent is added only for those, so a unique project stays one word.
function labelMap(sessions, home) {
  var keysByLabel = {}
  for (var i = 0; i < sessions.length; i++) {
    var key = sessions[i].key
    var label = projectLabel(key, home)
    if (!keysByLabel[label]) keysByLabel[label] = []
    if (keysByLabel[label].indexOf(key) === -1) keysByLabel[label].push(key)
  }
  var map = {}
  for (var base in keysByLabel) {
    var keys = keysByLabel[base]
    for (var k = 0; k < keys.length; k++) {
      var parts = cleanPath(keys[k]).split("/").filter(function(part) { return part })
      map[keys[k]] = keys.length > 1 && parts.length >= 2
        ? parts[parts.length - 2] + "/" + parts[parts.length - 1]
        : base
    }
  }
  return map
}

function matches(session, query) {
  var text = str(query).trim().toLowerCase()
  if (!text) return true
  var hay = (session.title + " " + session.project + " " + session.cwd + " " + toolLabel(session.tool) + " " + session.tool).toLowerCase()
  var words = text.split(/\s+/)
  for (var i = 0; i < words.length; i++) {
    if (hay.indexOf(words[i]) === -1) return false
  }
  return true
}

function relativeTime(updated, now) {
  if (!updated) return ""
  var delta = Math.max(0, (now || 0) - updated)
  if (delta < 45000) return "just now"
  if (delta < 3600000) return Math.round(delta / 60000) + "m"
  if (delta < 86400000) return Math.round(delta / 3600000) + "h"
  if (delta < 7 * 86400000) return Math.round(delta / 86400000) + "d"
  var date = new Date(updated)
  return date.getDate() + " " + MONTHS[date.getMonth()]
}

// Headers plus the sessions under them. Each folder appears once, placed
// by its newest session, with its sessions newest first beneath it.
// `cursor` counts only the sessions, in the order they are shown, which is
// what the keyboard moves through. `running` marks the ids a window already has.
function rows(sessions, query, tool, now, home, running) {
  var wanted = str(tool).trim()
  var groups = []
  var groupOf = {}
  var matched = []
  var source = sessions || []
  for (var i = 0; i < source.length && matched.length < LIST_LIMIT; i++) {
    if (wanted && source[i].tool !== wanted) continue
    if (!matches(source[i], query)) continue
    matched.push(source[i])
    var key = source[i].key
    if (!groupOf[key]) {
      groupOf[key] = []
      groups.push(key)
    }
    groupOf[key].push(source[i])
  }
  var labels = labelMap(matched, home)
  var out = []
  var cursor = 0
  for (var g = 0; g < groups.length; g++) {
    var members = groupOf[groups[g]]
    var label = labels[groups[g]] || members[0].project
    out.push({ kind: "header", project: label, cwd: members[0].cwd, count: members.length })
    for (var m = 0; m < members.length; m++) {
      var session = members[m]
      out.push({
        kind: "session",
        cursor: cursor,
        tool: session.tool,
        toolLabel: toolLabel(session.tool),
        id: session.id,
        cwd: session.cwd,
        title: session.title,
        project: label,
        when: relativeTime(session.updated, now),
        running: !!(running && running[session.id])
      })
      cursor += 1
    }
  }
  return { rows: out, count: cursor }
}

function toolsPresent(sessions) {
  var seen = {}
  var list = sessions || []
  for (var i = 0; i < list.length; i++) seen[list[i].tool] = true
  var out = []
  for (var t = 0; t < TOOLS.length; t++) {
    if (seen[TOOLS[t]]) out.push({ id: TOOLS[t], label: toolLabel(TOOLS[t]) })
  }
  return out
}

// The chip `delta` steps from the current one, round the ends, so Tab and
// Shift+Tab cycle All and each tool.
function nextTool(chips, current, delta) {
  var list = chips || []
  if (!list.length) return ""
  var at = 0
  for (var i = 0; i < list.length; i++) {
    if (list[i].id === current) at = i
  }
  return list[((at + delta) % list.length + list.length) % list.length].id
}

// What to run inside the terminal. Grok keeps its sessions per directory,
// so the directory goes on the command as well as on the terminal.
function resumeArgv(session) {
  if (!session || !session.id) return null
  if (session.tool === "claude") return ["claude", "--resume", session.id]
  if (session.tool === "grok") {
    var argv = ["grok", "--resume", session.id]
    if (session.cwd) argv.splice(1, 0, "--cwd", session.cwd)
    return argv
  }
  if (session.tool === "codex") return ["codex", "resume", session.id]
  if (session.tool === "cursor") return ["agent", "--resume", session.id]
  return null
}

// A fresh conversation with the same tool, for Ctrl+Enter. The terminal is
// opened in the session's directory, which is where each tool starts.
function newArgv(tool) {
  if (tool === "claude") return ["claude"]
  if (tool === "grok") return ["grok"]
  if (tool === "codex") return ["codex"]
  if (tool === "cursor") return ["agent"]
  return null
}

// A window already running this session. scan.py gathers, per window, the
// command lines, open files and recorded session ids of every process in
// it; the id has to be among them. Sharing a directory is not enough,
// since several terminals do.
function matchClient(session, clients) {
  var id = session && session.id ? String(session.id) : ""
  if (!id) return null
  var list = clients || []
  for (var i = 0; i < list.length; i++) {
    var text = str(list[i] && list[i].text)
    if (text && text.indexOf(id) !== -1 && list[i].address) return list[i]
  }
  return null
}

// The multiplexer pane inside `client` that runs this session, if any.
function matchPane(session, client) {
  var id = session && session.id ? String(session.id) : ""
  var panes = (client && client.panes) || []
  if (!id) return null
  for (var i = 0; i < panes.length; i++) {
    if (str(panes[i].text).indexOf(id) !== -1 && panes[i].pane) return panes[i]
  }
  return null
}

// ---------------------------------------------------------------- opening

var APP_LABELS = { herdr: "herdr", tmux: "tmux", terminal: "Terminal" }

// Where a session opens: where it was opened last, when that app is still
// installed; else the default; else a plain terminal.
function appFor(session, apps) {
  var available = (apps && apps.available) || ["terminal"]
  var remembered = session && apps && apps.sessions ? apps.sessions[session.id] : ""
  if (remembered && available.indexOf(remembered) !== -1) return remembered
  if (apps && apps.default && available.indexOf(apps.default) !== -1) return apps.default
  return "terminal"
}

function appChoices(apps) {
  var available = (apps && apps.available) || ["terminal"]
  var out = []
  for (var i = 0; i < available.length; i++) out.push({ id: available[i], label: APP_LABELS[available[i]] || available[i] })
  return out
}

// The arguments for `scan.py open`: the app, the folder, a title for the
// tab, the session to remember it for (or "-") and what to run.
function openArgs(app, row, argv, remember) {
  return ["open", app, (row && row.cwd) || "", (row && row.title) || "", remember && row && row.id ? row.id : "-"].concat(argv || [])
}

// "herdr" or "tmux" when the session runs in one of their panes, else "".
function paneKindOf(session, clients) {
  var client = matchClient(session, clients)
  var pane = client ? matchPane(session, client) : null
  return pane && pane.kind ? pane.kind : ""
}

// `id=app` for each session found running in a herdr or tmux pane that is
// not yet remembered that way, so sessions started by hand are remembered.
function panesToRemember(sessions, clients, apps) {
  var out = []
  var list = sessions || []
  var known = (apps && apps.sessions) || {}
  for (var i = 0; i < list.length; i++) {
    var kind = paneKindOf(list[i], clients)
    if (kind && known[list[i].id] !== kind) out.push(list[i].id + "=" + kind)
  }
  return out
}

// The sessions some window is already running, as { id: true }.
function runningIds(sessions, clients) {
  var running = {}
  var list = sessions || []
  if (!clients || !clients.length) return running
  for (var i = 0; i < list.length; i++) {
    if (matchClient(list[i], clients)) running[list[i].id] = true
  }
  return running
}

// ---------------------------------------------------------------- usage

var USAGE_ORDER = ["claude", "grok", "codex", "cursor", "fireworks"]
var COST_TICKS_PER_USD = 1e10

function formatTokens(n) {
  var value = Number(n)
  if (!isFinite(value)) return "0"
  var sign = value < 0 ? "-" : ""
  value = Math.abs(value)
  if (value >= 1e9) return sign + trimNumber(value / 1e9) + "B"
  if (value >= 1e6) return sign + trimNumber(value / 1e6) + "M"
  if (value >= 1e3) return sign + trimNumber(value / 1e3) + "K"
  return sign + String(Math.round(value))
}

function trimNumber(value) {
  var text = value.toFixed(1)
  if (text.slice(-2) === ".0") return text.slice(0, -2)
  return text
}

function formatUsdFromTicks(ticks) {
  var usd = (Number(ticks) || 0) / COST_TICKS_PER_USD
  if (!(usd > 0)) return ""
  if (usd >= 100) return "$" + Math.round(usd)
  return "$" + usd.toFixed(2)
}

function formatPercent(p) {
  var n = Number(p)
  if (!isFinite(n) || n < 0) return ""
  return Math.round(n * 100) + "%"
}

function clamp01(n) {
  n = Number(n)
  if (!isFinite(n) || n < 0) return 0
  if (n > 1) return 1
  return n
}

function shortLimit(label) {
  var text = str(label).toLowerCase()
  if (text.indexOf("week") !== -1) return "week"
  if (text.indexOf("session") !== -1) return "session"
  if (text.indexOf("month") !== -1) return "month"
  if (text.indexOf("day") !== -1) return "day"
  return str(label)
}

function pad2(n) {
  return n < 10 ? "0" + n : String(n)
}

// When an allowance renews: a countdown inside a day, the weekday and time
// inside a week, the date beyond that. Local time, as the clock shows it.
function resetLabel(iso, now) {
  var at = Date.parse(str(iso))
  if (!isFinite(at)) return ""
  var minutes = Math.round((at - (now || 0)) / 60000)
  if (minutes <= 0) return "renews now"
  if (minutes < 60) return "renews in " + minutes + "m"
  if (minutes < 24 * 60) {
    var rest = minutes % 60
    return "renews in " + Math.floor(minutes / 60) + "h" + (rest ? " " + rest + "m" : "")
  }
  var date = new Date(at)
  if (minutes < 7 * 24 * 60) {
    return "renews " + DAYS[date.getDay()] + " " + pad2(date.getHours()) + ":" + pad2(date.getMinutes())
  }
  return "renews " + date.getDate() + " " + MONTHS[date.getMonth()]
}

function localDate(ms) {
  var d = new Date(ms)
  return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate())
}

// The last seven days, oldest first and ending today, from [{ date, tokens }]
// records. A day with nothing recorded is there with nothing, so the rows
// always read as a week.
function dayRows(days, now) {
  var byDate = {}
  var list = days || []
  for (var i = 0; i < list.length; i++) {
    if (!list[i] || !list[i].date) continue
    byDate[list[i].date] = (byDate[list[i].date] || 0) + (Number(list[i].tokens) || 0)
  }
  var rows = []
  var max = 0
  var any = false
  for (var back = 6; back >= 0; back--) {
    var at = (now || 0) - back * 86400000
    var date = localDate(at)
    var tokens = byDate[date] || 0
    if (tokens > 0) any = true
    if (tokens > max) max = tokens
    rows.push({ date: date, day: DAYS[new Date(at).getDay()], tokens: tokens, today: back === 0 })
  }
  if (!any) return []
  for (var r = 0; r < rows.length; r++) {
    rows[r].label = rows[r].tokens > 0 ? formatTokens(rows[r].tokens) : ""
    rows[r].share = max > 0 ? rows[r].tokens / max : 0
  }
  return rows
}

function activityLabel(prompts, sessions) {
  var bits = []
  if (prompts > 0) bits.push(prompts + (prompts === 1 ? " prompt" : " prompts"))
  if (sessions > 0) bits.push(sessions + (sessions === 1 ? " session" : " sessions"))
  return bits.join(" · ")
}

function modelWordCase(word) {
  if (word === "gpt") return "GPT"
  if (word === "deepseek") return "DeepSeek"
  return word.charAt(0).toUpperCase() + word.slice(1)
}

// `claude-opus-4-8` becomes "Opus 4.8". The vendor prefix is dropped because
// the row already says which subscription it belongs to.
function friendlyModelName(id) {
  if (!id) return "Unknown"
  var name = String(id).replace(/^claude-/, "").replace(/^grok-/, "").replace(/-\d{8}$/, "")
  var parts = name.split("-")
  var words = []
  var version = []
  for (var i = 0; i < parts.length; i++) {
    var part = parts[i]
    if (part === "") continue
    if (/^\d/.test(part)) {
      version.push(part)
      continue
    }
    if (version.length > 0) {
      words.push(version.join("."))
      version = []
    }
    words.push(modelWordCase(part))
  }
  if (version.length > 0) words.push(version.join("."))
  return words.length > 0 ? words.join(" ") : "Unknown"
}

function bucketTotal(bucket) {
  return (Number(bucket.input) || 0) + (Number(bucket.output) || 0)
    + (Number(bucket.cacheRead) || 0) + (Number(bucket.cacheWrite) || 0)
}

function mergeModels(lists) {
  var byId = {}
  var order = []
  for (var i = 0; i < lists.length; i++) {
    var models = lists[i] || []
    for (var m = 0; m < models.length; m++) {
      var model = models[m]
      if (!model || !model.id) continue
      if (!byId[model.id]) {
        byId[model.id] = { id: model.id, input: 0, output: 0, cacheRead: 0, cacheWrite: 0, costTicks: 0 }
        order.push(model.id)
      }
      var into = byId[model.id]
      into.input += Number(model.input) || 0
      into.output += Number(model.output) || 0
      into.cacheRead += Number(model.cacheRead) || 0
      into.cacheWrite += Number(model.cacheWrite) || 0
      into.costTicks += Number(model.costTicks) || 0
    }
  }
  var out = []
  for (var n = 0; n < order.length; n++) out.push(byId[order[n]])
  return out
}

function modelRows(models) {
  var rows = []
  var max = 0
  for (var i = 0; i < models.length; i++) {
    var total = bucketTotal(models[i])
    var cost = formatUsdFromTicks(models[i].costTicks)
    if (total <= 0 && !cost) continue
    if (total > max) max = total
    var bits = []
    if (models[i].input) bits.push("in " + formatTokens(models[i].input))
    if (models[i].output) bits.push("out " + formatTokens(models[i].output))
    if (models[i].cacheRead) bits.push("cache " + formatTokens(models[i].cacheRead))
    rows.push({
      name: friendlyModelName(models[i].id),
      total: total,
      totalLabel: formatTokens(total),
      cost: cost,
      detail: bits.join(" · ")
    })
  }
  rows.sort(function(a, b) { return b.total - a.total })
  if (rows.length > 4) rows = rows.slice(0, 4)
  for (var r = 0; r < rows.length; r++) rows[r].share = max > 0 ? clamp01(rows[r].total / max) : 0
  return rows
}

// scan.py hands every percent over as a fraction, so 1.2 is a plan
// 20% past its allowance, not 1.2%.
function fraction(value) {
  if (value === null || value === undefined || value === "") return null
  var n = Number(value)
  if (!isFinite(n) || n < 0) return null
  return n
}

function limitRow(label, short, percent, reset) {
  return {
    label: label,
    short: short,
    percent: clamp01(percent),
    text: formatPercent(percent),
    reset: reset || "",
    warning: percent >= 0.75 && percent < 0.9,
    alarming: percent >= 0.9
  }
}

var SPAN_ORDER = ["month", "included", "week", "day", "session"]

// Longest span first, so every tool opens on its week or month, and a
// limit with no span keeps its place after those.
function bySpan(limits) {
  var rank = function(limit) {
    var at = SPAN_ORDER.indexOf(limit.short)
    return at < 0 ? SPAN_ORDER.length : at
  }
  return limits
    .map(function(limit, at) { return { limit: limit, at: at } })
    .sort(function(a, b) { return rank(a.limit) - rank(b.limit) || a.at - b.at })
    .map(function(entry) { return entry.limit })
}

// The allowances worth a line of their own at a glance: the ones that
// renew, like Claude's session and week. Shares inside an allowance, like
// Grok's Build and Chat, have no renewal of their own and wait for the
// full view. When nothing carries a renewal the first limit stands in.
function summaryOf(limits) {
  var out = []
  for (var i = 0; i < limits.length; i++) {
    if (limits[i].reset) out.push(limits[i])
  }
  if (!out.length && limits.length) out.push(limits[0])
  return out
}

function subscriptionPanel(raw, now) {
  if (!raw || !raw.id) return null
  var limits = []
  var source = raw.limits || []
  for (var i = 0; i < source.length && limits.length < 3; i++) {
    var percent = fraction(source[i].percent)
    if (percent === null) continue
    limits.push(limitRow(str(source[i].label), shortLimit(source[i].label), percent,
      resetLabel(source[i].resetsAt, now)))
  }
  limits = bySpan(limits)
  var models = modelRows(raw.models || [])
  var today = Number(raw.todayTokens) || 0
  if (!limits.length && today <= 0 && !models.length) return null
  return {
    id: raw.id,
    name: str(raw.name) || toolLabel(raw.id),
    tier: str(raw.tier),
    todayLabel: today > 0 ? "today " + formatTokens(today) : "",
    summary: summaryOf(limits),
    limits: limits,
    models: models,
    days: dayRows(raw.days, now),
    activity: activityLabel(Number(raw.todayPrompts) || 0, Number(raw.todaySessions) || 0),
    status: str(raw.status),
    help: str(raw.help)
  }
}

function cursorPanel(allowance, now) {
  if (!allowance) return null
  var included = fraction(allowance.percent)
  if (included === null) return null
  var limits = [limitRow("Included", "included", included, resetLabel(allowance.resetsAt, now))]
  var products = allowance.products || []
  for (var i = 0; i < products.length; i++) {
    var share = fraction(products[i].percent)
    if (share === null) continue
    var label = str(products[i].name)
    limits.push(limitRow(label, label.toLowerCase(), share, ""))
  }
  if (allowance.onDemand === "off") {
    limits.push({
      label: "On-Demand",
      short: "on-demand",
      percent: 0,
      text: "Disabled",
      reset: "",
      warning: false,
      alarming: false
    })
  }
  return {
    id: "cursor",
    name: "Cursor",
    tier: str(allowance.plan),
    todayLabel: "",
    summary: summaryOf(limits),
    limits: limits,
    models: [],
    days: [],
    activity: "",
    status: "",
    help: ""
  }
}

function grokProductLabel(name) {
  var text = str(name)
  if (text === "GrokBuild" || text === "Build") return "Build"
  if (text === "GrokChat" || text === "Chat") return "Chat"
  return text
}

function grokPanel(sessions, allowance, now) {
  var lists = []
  var source = sessions || []
  for (var i = 0; i < source.length; i++) lists.push(source[i] && source[i].models)
  var merged = mergeModels(lists)
  var models = modelRows(merged)
  var limits = []
  var week = allowance ? fraction(allowance.percent) : null
  if (week !== null) {
    limits.push(limitRow("Weekly", "week", week, resetLabel(allowance.resetsAt, now)))
    var products = allowance.products || []
    for (var p = 0; p < products.length && limits.length < 3; p++) {
      var share = fraction(products[p].percent)
      if (share === null) continue
      var label = grokProductLabel(products[p].name)
      limits.push(limitRow(label, label.toLowerCase(), share, ""))
    }
  }
  if (!models.length && !limits.length) return null
  var ticks = 0
  var tokens = 0
  for (var m = 0; m < merged.length; m++) {
    ticks += Number(merged[m].costTicks) || 0
    tokens += bucketTotal(merged[m])
  }
  var cost = formatUsdFromTicks(ticks)
  var parts = []
  if (cost) parts.push(cost)
  if (tokens > 0) parts.push(formatTokens(tokens))
  var recorded = parts.join(" · ")
  return {
    id: "grok",
    name: "Grok",
    tier: limits.length ? "" : "on this machine",
    todayLabel: recorded,
    summary: summaryOf(limits),
    limits: limits,
    models: models,
    days: dayRows(grokDays(source), now),
    activity: "",
    status: "",
    help: ""
  }
}

// Grok's session files, as tokens on the day each session was last active.
function grokDays(sessions) {
  var days = []
  for (var i = 0; i < sessions.length; i++) {
    var session = sessions[i]
    if (!session || !session.day) continue
    var tokens = 0
    var models = session.models || []
    for (var m = 0; m < models.length; m++) tokens += bucketTotal(models[m])
    days.push({ date: session.day, tokens: tokens })
  }
  return days
}

// One entry per subscription that has a limit or any recorded tokens.
// Grok is summed from the session usage files. Codex and Fireworks appear
// once their collector has something to say.
function usageFrom(subscriptions, grokSessions, now, allowance, cursorAllowance) {
  var panels = []
  var list = subscriptions || []
  for (var i = 0; i < list.length; i++) {
    if (list[i] && list[i].id === "grok") continue
    var panel = subscriptionPanel(list[i], now)
    if (panel) panels.push(panel)
  }
  var grok = grokPanel(grokSessions, allowance, now)
  if (grok) panels.push(grok)
  var cursor = cursorPanel(cursorAllowance, now)
  if (cursor) panels.push(cursor)
  panels.sort(function(a, b) {
    var ai = USAGE_ORDER.indexOf(a.id)
    var bi = USAGE_ORDER.indexOf(b.id)
    if (ai < 0) ai = USAGE_ORDER.length
    if (bi < 0) bi = USAGE_ORDER.length
    if (ai !== bi) return ai - bi
    return a.name < b.name ? -1 : a.name > b.name ? 1 : 0
  })
  return panels
}

var BAR_FULLEST = "fullest"

// What the bar can be set to show: whichever allowance is fullest, or one
// tool's own, for each tool that has an allowance.
function barChoices(panels) {
  var out = [{ id: BAR_FULLEST, label: "Fullest" }]
  var list = panels || []
  for (var i = 0; i < list.length; i++) {
    if ((list[i].summary || []).length) out.push({ id: list[i].id, label: toolLabel(list[i].id) })
  }
  return out
}

// What the bar shows: the fullest allowance of the chosen tool, or of any
// tool when the choice is "fullest" or names one with nothing to show.
function barSummary(panels, choice) {
  var list = panels || []
  var wanted = str(choice) || BAR_FULLEST
  var fullest = null
  var owner = null
  var fallback = null
  var fallbackOwner = null
  for (var i = 0; i < list.length; i++) {
    var lines = list[i].summary || []
    for (var l = 0; l < lines.length; l++) {
      if (!fallback || lines[l].percent > fallback.percent) {
        fallback = lines[l]
        fallbackOwner = list[i]
      }
      if (list[i].id === wanted && (!fullest || lines[l].percent > fullest.percent)) {
        fullest = lines[l]
        owner = list[i]
      }
    }
  }
  if (!fullest) {
    fullest = fallback
    owner = fallbackOwner
  }
  if (!fullest) return null
  return {
    tool: owner.id,
    percent: fullest.percent,
    text: fullest.text,
    warning: fullest.warning,
    alarming: fullest.alarming
  }
}

// A tool's name with the share its fullest allowance has used, for the
// popup's switch: "Claude 47%".
function switchLabel(panel) {
  if (!panel) return ""
  var summary = barSummary([panel], panel.id)
  return toolLabel(panel.id) + (summary ? " " + summary.text : "")
}
