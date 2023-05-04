import ../clap
import ../userplugin

var extension* = clap.PluginTimerSupport(
  onTimer: proc(clapPlugin: ptr clap.Plugin, timerId: clap.Id) {.cdecl.} =
    let plugin = clapPlugin.getUserPlugin()
    if plugin.timerIdToProcTable.hasKey(timerId):
      plugin.timerIdToProcTable[timerId](plugin)
)