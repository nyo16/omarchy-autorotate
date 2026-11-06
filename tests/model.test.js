// Run with: node tests/model.test.js
// Model.js has no exports (QML imports it as-is), so it is evaluated here rather than required.

const fs = require("fs")
const path = require("path")

const source = fs.readFileSync(path.join(__dirname, "..", "Model.js"), "utf8")
const Model = new Function(
  source + "; return { normalizeConfig, nextMode, parseSensorLine, rotationActive, desiredTransform, rotateLua, findMonitor }"
)()

let failures = 0

function check(name, actual, expected) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    failures++
    console.log("FAIL " + name + "\n  expected " + JSON.stringify(expected) + "\n  got      " + JSON.stringify(actual))
  }
}

// Lines as iio-sensor-proxy 3.9's monitor-sensor prints them.
check("initial state carries availability and orientation",
  Model.parseSensorLine("=== Has accelerometer (orientation: left-up, tilt: vertical)"),
  { available: true, orientation: "left-up" })
check("orientation change",
  Model.parseSensorLine("    Accelerometer orientation changed: bottom-up"), { orientation: "bottom-up" })
check("undefined orientation is not a rotation",
  Model.parseSensorLine("    Accelerometer orientation changed: undefined"), null)
check("no accelerometer", Model.parseSensorLine("=== No accelerometer"), { available: false })
check("proxy restart drops the sensor",
  Model.parseSensorLine("--- iio-sensor-proxy vanished, waiting for it to appear"), { available: false })
check("accelerometer hotplug", Model.parseSensorLine("+++ Accelerometer appeared"), { available: true })
check("tilt lines say nothing", Model.parseSensorLine("    Tilt changed: tilted-down"), null)

// mode, tablet, locked, available, orientation
check("tablet mode follows the sensor when folded", Model.desiredTransform("tablet", true, false, true, "left-up"), 1)
check("tablet mode returns to normal in laptop posture", Model.desiredTransform("tablet", false, false, true, "left-up"), 0)
check("always ignores the posture", Model.desiredTransform("always", false, false, true, "right-up"), 3)
check("off restores normal", Model.desiredTransform("off", true, false, true, "bottom-up"), 0)
check("lock holds the screen while folded", Model.desiredTransform("tablet", true, true, true, "left-up"), -1)
check("leaving tablet mode resets even when locked", Model.desiredTransform("tablet", false, true, true, "left-up"), 0)
check("no sensor leaves the screen alone", Model.desiredTransform("always", false, false, false, "left-up"), -1)

check("config defaults", Model.normalizeConfig(null), { mode: "tablet", locked: false, monitor: "eDP-1" })
check("config rejects unknown mode and unsafe monitor",
  Model.normalizeConfig({ mode: "sideways", locked: "yes", monitor: "eDP-1\" }) os.execute(\"x" }),
  { mode: "tablet", locked: false, monitor: "eDP-1" })
check("mode cycle wraps", [Model.nextMode("tablet"), Model.nextMode("always"), Model.nextMode("off")], ["always", "off", "tablet"])

const edp = { name: "eDP-1", width: 2880, height: 1800, refreshRate: 120.00099, x: 0, y: 0, scale: 2 }
check("rotate keeps mode, position and scale",
  Model.rotateLua(edp, 1),
  'hl.monitor({ output = "eDP-1", mode = "2880x1800@120.001", position = "0x0", scale = 2, transform = 1 })')
check("rotate refuses an out-of-range transform", Model.rotateLua(edp, 7), "")
check("rotate refuses an unsafe output name", Model.rotateLua(Object.assign({}, edp, { name: 'a"b' }), 1), "")
check("monitor lookup by name", Model.findMonitor([{ name: "DP-1" }, edp], "eDP-1"), edp)

if (failures) {
  console.log(failures + " failed")
  process.exit(1)
}
console.log("ok")
