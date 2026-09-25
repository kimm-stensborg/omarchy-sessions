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

// The title worth showing, in the order a person would recognize it.
// A name the tool generated beats the first line that was typed.
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
// what the keyboard moves through.
function rows(sessions, query, tool, now, home) {
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
    out.push({ kind: "header", project: label, cwd: members[0].cwd })
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
        when: relativeTime(session.updated, now)
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
    alarming: percent >= 0.9
  }
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
  var models = modelRows(raw.models || [])
  var today = Number(raw.todayTokens) || 0
  if (!limits.length && today <= 0 && !models.length) return null
  // The meter is the fullest allowance, and its renewal is the one shown.
  var headline = []
  var fullest = -1
  for (var h = 0; h < limits.length; h++) {
    headline.push(limits[h].short + " " + limits[h].text)
    if (fullest < 0 || limits[h].percent > limits[fullest].percent) fullest = h
  }
  var meter = fullest < 0 ? 0 : limits[fullest].percent
  return {
    id: raw.id,
    name: str(raw.name) || toolLabel(raw.id),
    tier: str(raw.tier),
    todayLabel: today > 0 ? "today " + formatTokens(today) : "",
    headline: headline.join(" · "),
    renews: fullest < 0 ? "" : limits[fullest].reset,
    meter: meter,
    alarming: meter >= 0.9,
    limits: limits,
    models: models
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
      alarming: false
    })
  }
  return {
    id: "cursor",
    name: "Cursor",
    tier: str(allowance.plan),
    todayLabel: "",
    headline: "included " + formatPercent(included),
    renews: limits[0].reset,
    meter: clamp01(included),
    alarming: included >= 0.9,
    limits: limits,
    models: []
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
    headline: limits.length ? limits[0].short + " " + limits[0].text : recorded,
    renews: limits.length ? limits[0].reset : "",
    meter: limits.length ? limits[0].percent : 0,
    alarming: limits.length ? limits[0].alarming : false,
    limits: limits,
    models: models
  }
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
