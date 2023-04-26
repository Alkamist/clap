import ../clap
import ../userplugin

proc getHostTimerSupport(plugin: UserPlugin): ptr clap.HostTimerSupport =
  cast[ptr clap.HostTimerSupport](plugin.clapHost.getExtension(plugin.clapHost, clap.extTimerSupport))

proc registerTimer*(plugin: UserPlugin, name: string, periodMs: int, timerProc: proc()) =
  var id: clap.Id
  let hostTimerSupport = plugin.getHostTimerSupport()
  discard hostTimerSupport.registerTimer(plugin.clapHost, uint32(periodMs), id.addr)
  plugin.timerNameToIdTable[name] = id
  plugin.timerIdToProcTable[id] = timerProc

proc unregisterTimer*(plugin: UserPlugin, name: string) =
  if plugin.timerNameToIdTable.hasKey(name):
    let id = plugin.timerNameToIdTable[name]
    let hostTimerSupport = plugin.getHostTimerSupport()
    discard hostTimerSupport.unregisterTimer(plugin.clapHost, id)
    plugin.timerIdToProcTable[id] = nil

var extension* = clap.PluginTimerSupport(
  onTimer: proc(clapPlugin: ptr clap.Plugin, timerId: clap.Id) {.cdecl.} =
    let plugin = clapPlugin.getUserPlugin()
    if plugin.timerIdToProcTable.hasKey(timerId):
      plugin.timerIdToProcTable[timerId]()
)