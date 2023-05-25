import std/tables
import ../binding

proc onTimer*[T](plugin: ptr clap_plugin_t, timer_id: clap_id) {.cdecl.} =
  let plugin = cast[T](plugin.plugin_data)
  if plugin.timerIdToProc.hasKey(timer_id):
    plugin.timerIdToProc[timerId](cast[pointer](plugin))