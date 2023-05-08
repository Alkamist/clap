import ../binding
import ../shared

var timerExtension* = clap_plugin_timer_support_t(
  on_timer: proc(plugin: ptr clap_plugin_t, timer_id: clap_id) {.cdecl.} =
    let instance = plugin.getInstance()
    if instance.timerIdToProcTable.hasKey(timer_id):
      instance.timerIdToProcTable[timerId](instance)
  ,
)