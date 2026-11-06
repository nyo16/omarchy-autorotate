// No QML imports on purpose, so every function here runs in a plain JS harness (tests/model.test.js).

var MODES = ["tablet", "always", "off"]

// iio-sensor-proxy orientation -> Hyprland monitor transform (0 normal, 1 90°, 2 180°, 3 270°).
var TRANSFORMS = { "normal": 0, "left-up": 1, "bottom-up": 2, "right-up": 3 }

var DEFAULT_CONFIG = { mode: "tablet", locked: false, monitor: "eDP-1" }

function normalizeConfig(raw) {
  var config = raw && typeof raw === "object" ? raw : {}
  var monitor = typeof config.monitor === "string" && isSafeName(config.monitor) ? config.monitor : DEFAULT_CONFIG.monitor
  return {
    mode: MODES.indexOf(config.mode) !== -1 ? config.mode : DEFAULT_CONFIG.mode,
    locked: config.locked === true,
    monitor: monitor
  }
}

function nextMode(mode) {
  var at = MODES.indexOf(mode)
  return MODES[(at + 1) % MODES.length]
}

// Output names end up inside a Lua string sent to Hyprland, so only plain names pass.
function isSafeName(name) {
  return /^[A-Za-z0-9._-]{1,64}$/.test(name)
}

// One line of `monitor-sensor --accel` -> { available?, orientation? } or null for lines that say nothing.
function parseSensorLine(line) {
  var text = String(line || "")
  if (text.indexOf("=== No accelerometer") !== -1
      || text.indexOf("--- Accelerometer disappeared") !== -1
      || text.indexOf("--- iio-sensor-proxy vanished") !== -1)
    return { available: false }

  var result = null
  if (text.indexOf("=== Has accelerometer") !== -1 || text.indexOf("+++ Accelerometer appeared") !== -1)
    result = { available: true }

  var match = /orientation(?: changed)?: ([a-z-]+)/.exec(text)
  if (match && TRANSFORMS.hasOwnProperty(match[1])) {
    result = result || {}
    result.orientation = match[1]
  }
  return result
}

// Whether the sensor should be driving the display at all.
function rotationActive(mode, tabletMode) {
  return mode === "always" || (mode === "tablet" && tabletMode === true)
}

// Transform the display should have, or -1 to leave it alone.
// Inactive returns to normal even when locked, so folding back into a laptop never
// leaves the desktop sideways. While active, the lock holds whatever is on screen.
function desiredTransform(mode, tabletMode, locked, sensorAvailable, orientation) {
  if (!rotationActive(mode, tabletMode)) return 0
  if (locked) return -1
  if (!sensorAvailable || !TRANSFORMS.hasOwnProperty(orientation)) return -1
  return TRANSFORMS[orientation]
}

function formatNumber(value) {
  var n = Number(value)
  if (!isFinite(n)) return "0"
  return String(Math.round(n * 1000) / 1000)
}

// Lua for `hyprctl eval` that rotates the output and keeps its current mode, position and scale.
// Touch and pen follow the output; their own transform rotates them to match.
function rotateLua(monitor, transform) {
  if (!monitor || !isSafeName(monitor.name)) return ""
  var t = Number(transform)
  if (!(t >= 0 && t <= 3)) return ""
  var mode = Math.round(monitor.width) + "x" + Math.round(monitor.height) + "@" + formatNumber(monitor.refreshRate)
  return "hl.monitor({ output = \"" + monitor.name + "\", mode = \"" + mode + "\""
    + ", position = \"" + Math.round(monitor.x) + "x" + Math.round(monitor.y) + "\""
    + ", scale = " + formatNumber(monitor.scale)
    + ", transform = " + t + " })"
}

function findMonitor(monitors, name) {
  if (!Array.isArray(monitors)) return null
  for (var i = 0; i < monitors.length; i++)
    if (monitors[i] && monitors[i].name === name) return monitors[i]
  return null
}
