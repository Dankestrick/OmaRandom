.pragma library

// Pure helpers for OmaRandom: data validation, colors, spin math and layout.
// Nothing here touches files, processes or the network.

var VERSION = 1
var MAX_WHEELS = 6
var MIN_OPTIONS = 2
var MAX_OPTIONS = 24
var MAX_NAME = 40
var MAX_LABEL = 40
var MAX_RESULTS = 500

// Bright colors that read well on any theme. Used when a wheel's palette is
// "Classic" and offered in the swatch picker.
var CLASSIC = ["#e53935", "#fb8c00", "#fdd835", "#43a047", "#00acc1", "#1e88e5",
               "#5e35b1", "#d81b60", "#6d4c41", "#00897b", "#c0ca33", "#8e24aa"]

// Theme keys read from colors.toml, in the order slices use them.
var THEME_KEYS = ["accent", "red", "orange", "yellow", "green", "cyan", "blue", "magenta",
                  "color1", "color2", "color3", "color4", "color5", "color6",
                  "bright_red", "bright_green", "bright_yellow", "bright_blue",
                  "bright_magenta", "bright_cyan"]

function isColor(s) {
  return typeof s === "string" && /^#[0-9A-Fa-f]{6}$/.test(s)
}

// Only local files: a picture can never make the shell fetch a URL.
function isLocalImage(s) {
  return typeof s === "string" && s.length < 4096 && /^file:\/\/\//.test(s)
}

function clip(s, max) {
  s = String(s === undefined || s === null ? "" : s).replace(/[\r\n\t]+/g, " ")
  return s.length > max ? s.substring(0, max) : s
}

function newId() {
  return Date.now().toString(36) + Math.floor(Math.random() * 1e9).toString(36)
}

// The colors in a theme's colors.toml, deduplicated, in THEME_KEYS order.
function themePalette(raw) {
  var found = {}
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var m = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
    if (m) found[m[1]] = m[2].toLowerCase()
  }
  var out = []
  for (var k = 0; k < THEME_KEYS.length; k++) {
    var c = found[THEME_KEYS[k]]
    if (c && out.indexOf(c) < 0) out.push(c)
  }
  return out.length >= 2 ? out : CLASSIC.slice()
}

function paletteFor(wheel, theme) {
  return wheel && wheel.palette === "classic" ? CLASSIC : (theme && theme.length ? theme : CLASSIC)
}

// The color a slice is drawn with: its own color, or the palette's. Two
// neighbors never share a color, including the last and the first.
function sliceColor(wheel, index, theme) {
  var opt = wheel.options[index]
  if (opt && isColor(opt.color)) return opt.color
  var pal = paletteFor(wheel, theme)
  var n = wheel.options.length
  var c = pal[index % pal.length]
  if (index === n - 1 && n > 1 && n % pal.length === 1) c = pal[(index + 1) % pal.length]
  return c
}

// Black or white text, whichever reads better on the color.
function textOn(c) {
  if (!isColor(c)) return "#ffffff"
  var r = parseInt(c.substr(1, 2), 16) / 255
  var g = parseInt(c.substr(3, 2), 16) / 255
  var b = parseInt(c.substr(5, 2), 16) / 255
  return (0.299 * r + 0.587 * g + 0.114 * b) > 0.6 ? "#000000" : "#ffffff"
}

function makeOption(label) {
  return { label: clip(label, MAX_LABEL), color: "", image: "" }
}

function makeWheel(name) {
  return {
    id: newId(),
    name: clip(name, MAX_NAME),
    palette: "theme",
    options: [makeOption("Option 1"), makeOption("Option 2"), makeOption("Option 3"), makeOption("Option 4")]
  }
}

function nextWheelName(wheels) {
  var n = 1
  var taken = {}
  for (var i = 0; i < wheels.length; i++) taken[wheels[i].name] = true
  while (taken["Wheel " + n]) n++
  return "Wheel " + n
}

function defaults() {
  return { version: VERSION, wheels: [makeWheel("Wheel 1")], results: [], shown: "" }
}

function cleanOption(o) {
  if (!o || typeof o !== "object") return null
  return {
    label: clip(o.label, MAX_LABEL),
    color: isColor(o.color) ? o.color : "",
    image: isLocalImage(o.image) ? o.image : ""
  }
}

function cleanWheel(w) {
  if (!w || typeof w !== "object" || !(w.options instanceof Array)) return null
  var opts = []
  for (var i = 0; i < w.options.length && opts.length < MAX_OPTIONS; i++) {
    var o = cleanOption(w.options[i])
    if (o) opts.push(o)
  }
  while (opts.length < MIN_OPTIONS) opts.push(makeOption("Option " + (opts.length + 1)))
  return {
    id: typeof w.id === "string" && w.id ? clip(w.id, 64) : newId(),
    name: clip(w.name, MAX_NAME) || "Wheel",
    palette: w.palette === "classic" ? "classic" : "theme",
    options: opts
  }
}

function cleanResult(r) {
  if (!r || typeof r !== "object") return null
  return {
    id: typeof r.id === "string" && r.id ? clip(r.id, 64) : newId(),
    batch: typeof r.batch === "string" ? clip(r.batch, 64) : "",
    wheelId: typeof r.wheelId === "string" ? clip(r.wheelId, 64) : "",
    wheel: clip(r.wheel, MAX_NAME),
    label: clip(r.label, MAX_LABEL),
    color: isColor(r.color) ? r.color : "",
    image: isLocalImage(r.image) ? r.image : "",
    time: typeof r.time === "number" && isFinite(r.time) ? r.time : 0
  }
}

// Parses the saved file. Returns { ok, data } or { ok: false, error }.
// An empty string means a first run.
function parse(raw) {
  var text = String(raw || "").trim()
  if (!text) return { ok: true, data: defaults(), fresh: true }
  var obj
  try { obj = JSON.parse(text) } catch (e) { return { ok: false, error: "not valid JSON" } }
  if (!obj || typeof obj !== "object" || !(obj.wheels instanceof Array))
    return { ok: false, error: "missing the wheels list" }
  if (typeof obj.version === "number" && obj.version > VERSION)
    return { ok: false, error: "made by a newer OmaRandom" }
  var wheels = []
  for (var i = 0; i < obj.wheels.length && wheels.length < MAX_WHEELS; i++) {
    var w = cleanWheel(obj.wheels[i])
    if (w) wheels.push(w)
  }
  var results = []
  var list = obj.results instanceof Array ? obj.results : []
  for (var j = 0; j < list.length && results.length < MAX_RESULTS; j++) {
    var r = cleanResult(list[j])
    if (r) results.push(r)
  }
  var shown = typeof obj.shown === "string" ? clip(obj.shown, 64) : ""
  return { ok: true, data: { version: VERSION, wheels: wheels, results: results, shown: shown } }
}

function serialize(data) {
  return JSON.stringify({ version: VERSION, wheels: data.wheels, results: data.results,
                          shown: data.shown || "" }, null, 2) + "\n"
}

// ---------- Spin math ----------
// Slices start at the pointer (3 o'clock) and go clockwise. A wheel turned
// by `angle` degrees clockwise shows disc angle (-angle) under the pointer.

function norm(a) {
  a = a % 360
  return a < 0 ? a + 360 : a
}

function indexAt(angle, count) {
  if (count < 1) return -1
  var step = 360 / count
  return Math.min(count - 1, Math.floor(norm(-angle) / step))
}

// The angle to stop at so `winner` sits under the pointer, a few full turns
// past `from`. The stop point inside the slice is random but keeps clear of
// the edges, so the pointer never looks like it's on a line.
function targetAngle(from, winner, count) {
  var step = 360 / count
  var inside = 0.15 + Math.random() * 0.7
  var disc = (winner + inside) * step
  var turns = 5 + Math.floor(Math.random() * 3)
  return from + turns * 360 + norm(-disc - from)
}

function pickIndex(count) {
  return Math.floor(Math.random() * count)
}

// ---------- Layout ----------
// Rows of up to three wheels. One wheel sits in the middle; more fill out to
// the right and the row stays centered.
function rows(count) {
  if (count <= 3) return [count]
  return [3, count - 3]
}

// ---------- Results ----------

function timeText(ms) {
  if (!ms) return ""
  return Qt.formatDateTime(new Date(ms), "MMM d · h:mm AP")
}

// The round a result belongs to: its batch, or the result itself.
function roundOf(r) {
  return r.batch || r.id
}

// Splits results into the round shown at the top (oldest first) and the
// history (everything else, newest first). `shown` is a round key, "" for
// the newest round, or "none" when the top was cleared.
function splitShown(results, shown) {
  if (!results.length) return { top: [], history: [], key: "" }
  var key = shown === "none" ? "" : (shown || roundOf(results[0]))
  var top = []
  var history = []
  for (var i = 0; i < results.length; i++) {
    if (key && roundOf(results[i]) === key) top.push(results[i])
    else history.push(results[i])
  }
  // A shown round that no longer exists falls back to the newest one.
  if (!top.length && shown && shown !== "none") return splitShown(results, "")
  top.reverse()
  return { top: top, history: history, key: key }
}
