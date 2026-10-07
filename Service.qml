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
// The menu closing is not enough on its own: dismissing it with Escape and
// then pressing a shortcut looks the same from Hyprland's side. So a launch
// also has to show it came from the shell, not from a keybinding:
//   - windows: the menu's app list is the only thing in Omarchy that starts
//     apps through `uwsm-app -- gtk-launch`, which systemd registers as a
//     scope named app-*-gtk\x2dlaunch-*.scope. inotify on the app slice sees
//     that scope appear before the window does. (Walking from the window back
//     to a process would not work: a Chromium window belongs to the browser
//     that was already running, however it was asked for.)
//   - scripts: a process the shell started inherits the shell's environment,
//     and omarchy-launch-shell sets QS_* variables Hyprland's never has.
//   - layers (emojis, clipboard): no trace survives, so these still rely on
//     the time window alone.
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
  //   { "id": "fkcodes.key-promoter", "duration": 3500, "position": "bottom-right", "window": 3000, "showCount": true }
  // position: top-left | top-center | top-right | bottom-left | bottom-center | bottom-right
  property int duration: 3500
  property string position: "bottom-right"
  readonly property var positions: ["top-left", "top-center", "top-right", "bottom-left", "bottom-center", "bottom-right"]
  property int window: 3000
  property bool showCount: true

  property var binds: []
  property var counts: ({})
  property double armedAt: 0
  property int psRuns: 0

  // Launch-origin evidence, see the header comment.
  // Where uwsm puts app scopes: .../user@UID.service/app.slice/app-graphical.slice
  readonly property string appSlice: {
    var m = /\/run\/user\/(\d+)/.exec(Quickshell.env("XDG_RUNTIME_DIR") || "")
    return m ? "/sys/fs/cgroup/user.slice/user-" + m[1] + ".slice/user@" + m[1] + ".service/app.slice/app-graphical.slice" : ""
  }
  // An environment variable only shell-started processes carry. Read off this
  // very process, so if omarchy-launch-shell stops setting it we notice and
  // fall back to the time window instead of never promoting a script again.
  readonly property string shellMarker: {
    var names = ["QS_NO_RELOAD_POPUP", "QS_DISABLE_FILE_WATCHER"]
    for (var i = 0; i < names.length; i++) if (Quickshell.env(names[i])) return names[i]
    return ""
  }
  property bool launchWatchOk: false
  property int launchWatchRetries: 0
  property double launcherAt: 0

  function applySettings(raw) {
    try {
      var cfg = JSON.parse(raw || "{}")
      var list = Array.isArray(cfg.plugins) ? cfg.plugins : []
      for (var i = 0; i < list.length; i++) {
        var e = list[i]
        if (!e || e.id !== service.pluginId) continue
        if (e.duration !== undefined) duration = Math.max(500, parseInt(e.duration, 10) || 3500)
        if (e.position !== undefined) {
          var pos = String(e.position)
          if (pos === "top" || pos === "bottom") pos += "-center"
          if (positions.indexOf(pos) !== -1) position = pos
        }
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

  // Did the menu's app list launch something since (just before) it closed?
  // Without a working watcher this cannot be known, so fall back to timing.
  function fromLauncher() {
    return !launchWatchOk || launcherAt >= armedAt - 1000
  }

  function promote(bind) {
    disarm()
    toast.show(bind.combo, bind.description, bump(bind.combo))
  }

  Component.onCompleted: {
    bindsProc.running = true
    if (appSlice) launchWatch.running = true
  }

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
        if (hit && service.fromLauncher()) service.promote(hit)
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

  // Prints "<etimes> <shell|-> <args>" for processes younger than 4s, where
  // "shell" means the process environment carries the shell marker.
  Process {
    id: psProc
    command: ["bash", "-c", [
      "ps -eo etimes=,pid=,args= | while read -r et pid args; do",
      "  [ \"$et\" -le 3 ] || continue",
      "  tag=-",
      "  if [ -n \"$1\" ] && grep -qsz \"^$1=\" \"/proc/$pid/environ\"; then tag=shell; fi",
      "  printf '%s %s %s\\n' \"$et\" \"$tag\" \"$args\"",
      "done"
    ].join("\n"), "ps-scan", service.shellMarker]
    stdout: StdioCollector {
      onStreamFinished: {
        if (!service.armed()) return
        var hit = Promoter.matchProcesses(service.binds, text, 3, service.shellMarker !== "")
        if (hit) service.promote(hit)
      }
    }
  }

  // Scope directories appearing under the app slice, one name per line.
  Process {
    id: launchWatch
    command: ["inotifywait", "-m", "-q", "-e", "create", "--format", "%f", service.appSlice]
    onStarted: { service.launchWatchOk = true; service.launchWatchRetries = 0 }
    onExited: {
      service.launchWatchOk = false
      if (service.launchWatchRetries++ < 5) launchWatchRetry.restart()
      else console.warn("key-promoter: launch watcher gave up; falling back to the time window alone")
    }
    stdout: SplitParser {
      onRead: function(line) { if (Promoter.isLauncherScope(line)) service.launcherAt = Date.now() }
    }
    stderr: StdioCollector { onStreamFinished: if (text.length) console.warn("key-promoter inotifywait:", text) }
  }

  Timer {
    id: launchWatchRetry
    interval: 5000
    onTriggered: launchWatch.running = true
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
    function state(): string {
      return JSON.stringify({
        armed: service.armed(),
        launchWatch: service.launchWatchOk,
        appSlice: service.appSlice,
        shellMarker: service.shellMarker,
        msSinceLauncher: service.launcherAt ? Date.now() - service.launcherAt : null
      })
    }
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
