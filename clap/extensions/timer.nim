import ../binding
import ../shared

proc registerTimer*(instance: AudioPlugin, name: string, periodMs: int, timerProc: proc(plugin: AudioPlugin)) =
  var id: clap_id
  let hostTimerSupport = cast[ptr clap_host_timer_support_t](instance.clapHost.get_extension(instance.clapHost, CLAP_EXT_TIMER_SUPPORT))
  discard hostTimerSupport.registerTimer(instance.clapHost, uint32(periodMs), id.addr)
  instance.timerNameToIdTable[name] = id
  instance.timerIdToProcTable[id] = timerProc

proc unregisterTimer*(instance: AudioPlugin, name: string) =
  if instance.timerNameToIdTable.hasKey(name):
    let id = instance.timerNameToIdTable[name]
    let hostTimerSupport = cast[ptr clap_host_timer_support_t](instance.clapHost.get_extension(instance.clapHost, CLAP_EXT_TIMER_SUPPORT))
    discard hostTimerSupport.unregisterTimer(instance.clapHost, id)
    instance.timerIdToProcTable[id] = nil

var timerExtension* = clap_plugin_timer_support_t(
  onTimer: proc(plugin: ptr clap_plugin_t, timer_id: clap_id) {.cdecl.} =
    let instance = plugin.getInstance()
    if instance.timerIdToProcTable.hasKey(timer_id):
      instance.timerIdToProcTable[timerId](instance)
)