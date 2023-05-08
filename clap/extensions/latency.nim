import ../binding
import ../shared

var latencyExtension* = clap_plugin_latency_t(
  get: proc(plugin: ptr clap_plugin_t): uint32 {.cdecl.} =
    let instance = plugin.getInstance()
    return uint32(instance.latency)
  ,
)