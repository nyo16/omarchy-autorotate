import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import "Model.js" as Model

// One instance per shell. Reads orientation from iio-sensor-proxy, posture from
// the tablet-mode switch, and rotates the built-in display through Hyprland.
Item {
  id: root

  // Injected by omarchy-shell.
  property var shell: null
  property var manifest: null

  readonly property string configPath: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/omarchy/autorotate.json"
  // HP exposes the posture in sysfs; elsewhere the Hyprland switch binds are the only source.
  readonly property string hpTabletPath: "/sys/devices/platform/hp-wmi/tablet"

  property string mode: "tablet"
  property bool locked: false
  property string monitorName: "eDP-1"
  property bool configLoaded: false

  property bool tabletMode: false
  property bool sensorAvailable: false
  property string orientation: "normal"
  // Last transform this service applied; -1 until it has applied one.
  property int appliedTransform: -1

  readonly property bool active: Model.rotationActive(mode, tabletMode)
  readonly property int desiredTransform: Model.desiredTransform(mode, tabletMode, locked, sensorAvailable, orientation)

  onDesiredTransformChanged: scheduleApply()
  onConfigLoadedChanged: scheduleApply()

  function setMode(value) {
    if (Model.MODES.indexOf(value) === -1) return false
    mode = value
    saveConfig()
    return true
  }

  function cycleMode() {
    setMode(Model.nextMode(mode))
  }

  function setLocked(value) {
    locked = value === true
    saveConfig()
  }

  function toggleLock() {
    setLocked(!locked)
  }

  function setTabletMode(value) {
    tabletMode = value === true
  }

  function saveConfig() {
    configFile.setText(JSON.stringify({ mode: mode, locked: locked, monitor: monitorName }, null, 2) + "\n")
  }

  function applyConfig(raw) {
    var config = Model.normalizeConfig(raw)
    mode = config.mode
    locked = config.locked
    monitorName = config.monitor
    configLoaded = true
  }

  // Forget what was applied, so the next decision is written out even if it matches.
  function reassert() {
    appliedTransform = -1
    scheduleApply()
  }

  function scheduleApply() {
    if (configLoaded) applyDebounce.restart()
  }

  function apply() {
    var transform = desiredTransform
    if (transform < 0 || transform === appliedTransform) return
    if (monitorQuery.running || rotateProcess.running) {
      applyDebounce.restart()
      return
    }
    monitorQuery.transform = transform
    monitorQuery.running = true
  }

  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: {
      var parsed = null
      try { parsed = JSON.parse(text()) } catch (e) { parsed = null }
      root.applyConfig(parsed)
    }
    onLoadFailed: root.applyConfig(null)
    onFileChanged: reload()
  }

  // A burst of orientation changes ends in one rotation.
  Timer {
    id: applyDebounce
    interval: 150
    onTriggered: root.apply()
  }

  Process {
    id: monitorQuery
    property int transform: -1
    command: ["hyprctl", "-j", "monitors"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var monitors = null
        try { monitors = JSON.parse(text) } catch (e) { monitors = null }
        var monitor = Model.findMonitor(monitors, root.monitorName)
        if (!monitor) return
        // Already there (startup, or a reload that changed nothing): rewriting the rule would only modeset.
        if (monitor.transform === monitorQuery.transform) {
          root.appliedTransform = monitorQuery.transform
          return
        }
        var lua = Model.rotateLua(monitor, monitorQuery.transform)
        if (!lua) return
        rotateProcess.transform = monitorQuery.transform
        rotateProcess.command = ["hyprctl", "eval", lua]
        rotateProcess.running = true
      }
    }
  }

  Process {
    id: rotateProcess
    property int transform: -1
    onExited: function(exitCode) {
      if (exitCode === 0) root.appliedTransform = transform
      else console.warn("autorotate: hyprctl eval exited " + exitCode)
      // The target may have moved while this one ran.
      if (root.desiredTransform >= 0 && root.desiredTransform !== root.appliedTransform) root.scheduleApply()
    }
  }

  // Holding the claim keeps the accelerometer powered, so only claim it while it can rotate anything.
  // stdbuf: monitor-sensor prints through stdio, which a pipe would otherwise buffer.
  Process {
    id: sensor
    property double startedAt: 0
    command: ["stdbuf", "-oL", "monitor-sensor", "--accel"]
    running: root.configLoaded && root.active && !root.locked
    onRunningChanged: {
      if (running) startedAt = Date.now()
      else root.sensorAvailable = false
    }
    stdout: SplitParser {
      onRead: function(line) {
        var update = Model.parseSensorLine(line)
        if (!update) return
        if (update.available !== undefined) root.sensorAvailable = update.available
        if (update.orientation !== undefined) {
          root.sensorAvailable = true
          root.orientation = update.orientation
        }
      }
    }
    onExited: function(exitCode) {
      // Not installed or crashed: retry slowly instead of spinning.
      if (Date.now() - startedAt < 2000) console.warn("autorotate: monitor-sensor exited " + exitCode + "; is iio-sensor-proxy installed?")
      if (root.configLoaded && root.active && !root.locked) sensorRestart.restart()
    }
  }

  Timer {
    id: sensorRestart
    interval: 5000
    onTriggered: {
      if (root.configLoaded && root.active && !root.locked && !sensor.running) sensor.running = true
    }
  }

  Process {
    id: hpTabletProbe
    command: ["cat", root.hpTabletPath]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var value = text.trim()
        if (value === "0" || value === "1") root.tabletMode = value === "1"
      }
    }
  }

  // A config reload re-reads monitors.lua and undoes the rotation; the panel coming
  // back (lid open, clamshell exit) starts unrotated too.
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name === "configreloaded") root.reassert()
      else if (event.name === "monitoradded" || event.name === "monitoraddedv2") root.reassert()
    }
  }

  Component.onCompleted: hpTabletProbe.running = true

  ShellIpc {
    target: "autorotate"

    function status(): string {
      return JSON.stringify({
        mode: root.mode,
        locked: root.locked,
        tabletMode: root.tabletMode,
        active: root.active,
        sensorAvailable: root.sensorAvailable,
        orientation: root.orientation,
        transform: root.appliedTransform,
        monitor: root.monitorName
      })
    }

    // tablet on|off, from the Hyprland switch binds.
    function tablet(state: string): string {
      root.setTabletMode(state === "on" || state === "1" || state === "true")
      return root.tabletMode ? "on" : "off"
    }

    function mode(value: string): string {
      return root.setMode(value) ? root.mode : "unknown mode: " + value
    }

    function cycle(): string {
      root.cycleMode()
      return root.mode
    }

    function lock(): string {
      root.setLocked(true)
      return "locked"
    }

    function unlock(): string {
      root.setLocked(false)
      return "unlocked"
    }

    function toggleLock(): string {
      root.toggleLock()
      return root.locked ? "locked" : "unlocked"
    }
  }
}
