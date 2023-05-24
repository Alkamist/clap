import ../binding

proc get*[T](plugin: ptr clap_plugin_t): uint32 {.cdecl.} =
  let plugin = cast[T](plugin.plugin_data)
  return uint32(max(0, plugin.latency))