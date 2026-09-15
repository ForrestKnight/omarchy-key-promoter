import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "Promoter.js" as Promoter

// Key Promoter for Omarchy.
//
// Watches for the moment the Omarchy menu closes and, for a short window
// afterwards, checks whether what happened next already has a keybinding:
// a window opened (app or web app), a shell layer opened (emojis, clipboard),
// or an omarchy-* script started (screenshot, color picker, lock). If so, it
// shows the shortcut in a small themed toast.
//
// Bindings are read from this machine, not from Omarchy's defaults, via
// bin/keybinds, which reuses the resolver behind SUPER + K.
Item {
  id: service

  // Injected by omarchy-shell.
  property var shell: null
  property var manifest: null
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")

  readonly property string home: Quickshell.env("HOME")
  readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : "fkcodes.key-promoter"
  readonly property string pluginDir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "").replace(/\/$/, "")
  readonly property string statePath: home + "/.local/state/omarchy/key-promoter.json"

  // Settings, inline on this plugin's entry in ~/.config/omarchy/shell.json:
  //   { "id": "fkcodes.key-promoter", "duration": 3500, "position": "top", "window": 3000, "showCount": true }
  property int duration: 3500
  property string position: "top"
  property int window: 3000
  property bool showCount: true

  property var binds: []
  property var counts: ({})
  property double armedAt: 0
  property int psRuns: 0

  function applySettings(raw) {
    try {
      var cfg = JSON.parse(raw || "{}")
      var list = Array.isArray(cfg.plugins) ? cfg.plugins : []
      for (var i = 0; i < list.length; i++) {
        var e = list[i]
        if (!e || e.id !== service.pluginId) continue
        if (e.duration !== undefined) duration = Math.max(500, parseInt(e.duration, 10) || 3500)
        if (e.position === "top" || e.position === "bottom") position = e.position
        if (e.window !== undefined) window = Math.max(500, parseInt(e.window, 10) || 3000)
        if (e.showCount !== undefined) showCount = e.showCount !== false
        return
      }
    } catch (err) {}
  }

  function loadBinds(raw) {
    try {
      binds = Promoter.prepare(JSON.parse(raw || "{}"))
    } catch (err) {
      console.warn("key-promoter: could not parse keybinds:", err)
    }
  }

  function loadCounts(raw) {
    try { counts = JSON.parse(raw || "{}") || {} } catch (err) { counts = {} }
  }

  function bump(combo) {
    var next = {}
    for (var k in counts) next[k] = counts[k]
    next[combo] = (next[combo] || 0) + 1
    counts = next
    stateFile.setText(JSON.stringify(counts, null, 2) + "\n")
    return next[combo]
  }

  function arm() {
    armedAt = Date.now()
    psRuns = 0
    psTimer.restart()
  }

  function armed() { return armedAt > 0 && Date.now() - armedAt <= window }

  function disarm() {
    armedAt = 0
    psTimer.stop()
  }

  function promote(bind) {
    disarm()
    toast.show(bind.combo, bind.description, bump(bind.combo))
  }

  Component.onCompleted: bindsProc.running = true

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = String(event.name)
      var data = String(event.data)
      if (name === "configreloaded") { bindsProc.running = true; return }
      if (name === "closelayer") { if (data === "omarchy-menu") service.arm(); return }
      if (!service.armed()) return
      if (name === "openwindow") {
        var parts = event.parse(4)
        var cls = parts.length > 2 ? parts[2] : ""
        var entry = cls ? DesktopEntries.heuristicLookup(cls) : null
        var hit = Promoter.matchWindow(service.binds, cls, entry)
        if (hit) service.promote(hit)
      } else if (name === "openlayer") {
        // The menu reopened (submenu, launcher); wait for what it does next.
        if (data === "omarchy-menu") { service.disarm(); return }
        var layerHit = Promoter.matchLayer(service.binds, data)
        if (layerHit) service.promote(layerHit)
      }
    }
  }

  // Scripts with no window of their own show up only in the process table.
  Timer {
    id: psTimer
    interval: 350
    repeat: true
    onTriggered: {
      if (!service.armed() || service.psRuns >= 3) { psTimer.stop(); return }
      service.psRuns++
      psProc.running = true
    }
  }

  Process {
    id: psProc
    command: ["ps", "-eo", "etimes=,args="]
    stdout: StdioCollector {
      onStreamFinished: {
        if (!service.armed()) return
        var hit = Promoter.matchProcesses(service.binds, text, 3)
        if (hit) service.promote(hit)
      }
    }
  }

  Process {
    id: bindsProc
    command: ["bash", service.pluginDir + "/bin/keybinds"]
    stdout: StdioCollector { onStreamFinished: service.loadBinds(text) }
    stderr: StdioCollector { onStreamFinished: if (text.length) console.warn("key-promoter keybinds:", text) }
  }

  FileView {
    id: shellConfig
    path: service.home + "/.config/omarchy/shell.json"
    watchChanges: true
    printErrors: false
    onLoaded: service.applySettings(text())
    onFileChanged: reload()
  }

  FileView {
    id: stateFile
    path: service.statePath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: service.loadCounts(text())
  }

  Toast {
    id: toast
    shell: service.shell
    duration: service.duration
    position: service.position
    showCount: service.showCount
  }

  IpcHandler {
    target: "key-promoter"
    function ping(): string { return "ok" }
    function reload(): string { bindsProc.running = true; return "ok" }
    function show(combo: string, description: string): string { toast.show(combo, description, 0); return "ok" }
    function hide(): string { toast.hide(); return "ok" }
    function stats(): string { return JSON.stringify(service.counts) }
    function resolved(): string {
      var out = []
      for (var i = 0; i < service.binds.length; i++) {
        var b = service.binds[i]
        if (b.sig && b.sig.kind !== "menu") out.push({ combo: b.combo, description: b.description, sig: b.sig })
      }
      return JSON.stringify(out)
    }
  }
}
