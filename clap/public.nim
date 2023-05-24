import ./types; export types
import ./binding
import ./plugin
import ./extensions/latency

# proc millisecondsToSamples*(plugin: AudioPlugin, milliseconds: float): int =
#   return int(plugin.sampleRate * milliseconds * 0.001)

# proc parameterCount*(plugin: AudioPlugin): int =
#   return plugin.parameterValues.len

# proc parameter*[T](plugin: AudioPlugin, id: T): float =
#   return plugin.parameterValues[int(id)].load()

# proc setParameter*[T](plugin: AudioPlugin, id: T, value: float) =
#   plugin.parameterValues[int(id)].store(value)

# proc resetParameterToDefault*[T](plugin: AudioPlugin, id: T) =
#   plugin.setParameter(id, plugin.dispatcher.parameterInfo[int(id)].defaultValue)

# proc registerTimer*(plugin: AudioPlugin, name: string, periodMs: int, timerProc: proc(plugin: AudioPlugin)) =
#   if plugin.clapHostTimerSupport == nil or
#      plugin.clapHostTimerSupport.registerTimer == nil:
#     return

#   var id: clap_id
#   discard plugin.clapHostTimerSupport.registerTimer(plugin.clapHost, uint32(periodMs), id.addr)
#   plugin.timerNameToId[name] = id
#   plugin.timerIdToProc[id] = timerProc

# proc unregisterTimer*(plugin: AudioPlugin, name: string) =
#   if plugin.clapHostTimerSupport == nil or
#      plugin.clapHostTimerSupport.unregisterTimer == nil:
#     return

#   if plugin.timerNameToId.hasKey(name):
#     let id = plugin.timerNameToId[name]
#     discard plugin.clapHostTimerSupport.unregisterTimer(plugin.clapHost, id)
#     plugin.timerIdToProc[id] = nil

# proc setLatency*(plugin: AudioPlugin, value: int) =
#   plugin.latency = value

#   if plugin.clapHostLatency == nil or
#      plugin.clapHostLatency.changed == nil or
#      plugin.clapHost.requestRestart == nil:
#     return

#   # Inform the host of the latency change
#   plugin.clapHostLatency.changed(plugin.clapHost)
#   if plugin.isActive:
#     plugin.clapHost.requestRestart(plugin.clapHost)

# proc sendMidiEvent*(plugin: AudioPlugin, event: MidiEvent) =
#   plugin.outputEvents.add(clap_event_midi_t(
#     header: clap_event_header_t(
#       size: uint32(sizeof(clap_event_midi_t)),
#       # after the bug in reaper gets fixed: time = uint32(event.time)
#       time: uint32(event.time - plugin.latency),
#       space_id: CLAP_CORE_EVENT_SPACE_ID,
#       type: CLAP_EVENT_MIDI,
#       flags: 0,
#     ),
#     port_index: uint16(event.port),
#     data: event.data,
#   ))

proc exportClapPlugin*[T](
  id: string,
  name: string,
  vendor: string,
  url: string,
  manualUrl: string,
  supportUrl: string,
  version: string,
  description: string,
) =
  var clapDescriptor {.global.}: clap_plugin_descriptor_t
  clapDescriptor.clap_version = CLAP_VERSION_INIT
  clapDescriptor.id = id
  clapDescriptor.name = name
  clapDescriptor.vendor = vendor
  clapDescriptor.url = url
  clapDescriptor.manualUrl = manualUrl
  clapDescriptor.supportUrl = supportUrl
  clapDescriptor.version = version
  clapDescriptor.description = description

  var clapExtensionLatency {.global.} = clap_plugin_latency_t(
    get: latency.get[T],
  )

  proc getExtension(plugin: ptr clap_plugin_t, id: cstring): pointer {.cdecl.} =
    # if id == CLAP_EXT_NOTE_PORTS: return addr(clapExtensionNotePorts)
    if id == CLAP_EXT_LATENCY: return addr(clapExtensionLatency)
    # if id == CLAP_EXT_PARAMS: return addr(clapExtensionParameters)
    # if id == CLAP_EXT_TIMER_SUPPORT: return addr(clapExtensionTimer)
    # if id == CLAP_EXT_STATE: return addr(clapExtensionState)
    # if id == CLAP_EXT_GUI: return addr(clapExtensionGui)
    return nil

  var clapFactory {.global.} = clap_plugin_factory_t(
    get_plugin_count: proc(factory: ptr clap_plugin_factory_t): uint32 {.cdecl.} =
      return 1
    ,
    get_plugin_descriptor: proc(factory: ptr clap_plugin_factory_t, index: uint32): ptr clap_plugin_descriptor_t {.cdecl.} =
      return addr(clapDescriptor)
    ,
    create_plugin: proc(factory: ptr clap_plugin_factory_t, host: ptr clap_host_t, plugin_id: cstring): ptr clap_plugin_t {.cdecl.} =
      if not clap_version_is_compatible(host.clap_version):
        return nil
      if pluginId == clapDescriptor.id:
        var plugin = T()
        GcRef(plugin)
        plugin.clapHost = host
        plugin.clapPlugin = clap_plugin_t(
          desc: addr(clapDescriptor),
          plugin_data: cast[pointer](plugin),
          init: pluginInit[T],
          destroy: pluginDestroy[T],
          activate: pluginActivate[T],
          deactivate: pluginDeactivate[T],
          start_processing: pluginStartProcessing,
          stop_processing: pluginStopProcessing,
          reset: pluginReset[T],
          process: pluginProcess[T],
          get_extension: getExtension,
          on_main_thread: pluginOnMainThread,
        )
        return addr(plugin.clapPlugin)
    ,
  )

  var clapEntry {.global, exportc: "clap_entry", dynlib.} = clap_plugin_entry_t(
    clap_version: CLAP_VERSION_INIT,
    init: proc(plugin_path: cstring): bool {.cdecl.} =
      return true
    ,
    deinit: proc() {.cdecl.} =
      discard
    ,
    get_factory: proc(factoryId: cstring): pointer {.cdecl.} =
      if factoryId == CLAP_PLUGIN_FACTORY_ID:
        return addr(clapFactory)
    ,
  )