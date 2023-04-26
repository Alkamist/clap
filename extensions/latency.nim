import ../clap
import ../userplugin

var extension* = clap.PluginLatency(
  get: proc(clapPlugin: ptr clap.Plugin): uint32 {.cdecl.} =
    let plugin = clapPlugin.getUserPlugin()
    return uint32(plugin.latency)
)