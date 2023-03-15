import ./clap/binding

type
  ParameterValueEvent* = object
    parameterId*: int
    note*: int
    port*: int
    channel*: int
    key*: int
    value*: float

  HostAudioBuffer* = ptr UncheckedArray[clap_audio_buffer_t]

  ClapPlugin* = ref object of RootObj
    sampleRate*: float

  ClapPluginInfo = ref object
    descriptor: clap_plugin_descriptor_t
    createInstance: proc(info: ClapPluginInfo): ptr clap_plugin_t

method processParameterValueEvent*(plugin: ClapPlugin, event: ParameterValueEvent) {.base.} = discard
method processAudio*(plugin: ClapPlugin, inputs, outputs: HostAudioBuffer, start, finish: int) {.base.} = discard

var pluginInfo: seq[ClapPluginInfo]

var clapPluginFactory = clap_plugin_factory_t(
  get_plugin_count: proc(factory: ptr clap_plugin_factory_t): uint32 {.cdecl.} =
    return pluginInfo.len.uint32

  , get_plugin_descriptor: proc(factory: ptr clap_plugin_factory_t, index: uint32): ptr clap_plugin_descriptor_t {.cdecl.} =
    return pluginInfo[index].descriptor.addr

  , create_plugin: proc(factory: ptr clap_plugin_factory_t, host: ptr clap_host_t, plugin_id: cstring): ptr clap_plugin_t {.cdecl.} =
    if not clap_version_is_compatible(host.clap_version):
      return nil

    for info in pluginInfo:
      if plugin_id == info.descriptor.id:
        return info.createInstance(info)

    return nil
)

proc NimMain() {.importc.}

proc init(plugin_path: cstring): bool {.cdecl.} =
  NimMain()
  return true

proc deinit() {.cdecl.} =
  discard

proc get_factory(factory_id: cstring): pointer {.cdecl.} =
  if factory_id == CLAP_PLUGIN_FACTORY_ID:
    return clapPluginFactory.addr

{.emit: """
CLAP_EXPORT const clap_plugin_entry_t clap_entry = {
  .clap_version = CLAP_VERSION_INIT,
  .init = `init`,
  .deinit = `deinit`,
  .get_factory = `get_factory`,
};
""".}

proc init(plugin: ptr clap_plugin_t): bool {.cdecl.} =
  return true

proc destroy(plugin: ptr clap_plugin_t) {.cdecl.} =
  GC_unref(cast[ClapPlugin](plugin.plugin_data))
  dealloc(plugin)
  discard

proc activate(plugin: ptr clap_plugin_t, sample_rate: cdouble, min_frames_count, max_frames_count: uint32): bool {.cdecl.} =
  let p = cast[ClapPlugin](plugin.plugin_data)
  p.sampleRate = sample_rate
  return true

proc deactivate(plugin: ptr clap_plugin_t) {.cdecl.} =
  discard

proc start_processing(plugin: ptr clap_plugin_t): bool {.cdecl.} =
  return true

proc stop_processing(plugin: ptr clap_plugin_t) {.cdecl.} =
  discard

proc reset(plugin: ptr clap_plugin_t) {.cdecl.} =
  discard

proc process(plugin: ptr clap_plugin_t, process: ptr clap_process_t): clap_process_status {.cdecl.} =
  let p = cast[ClapPlugin](plugin.plugin_data)

  let frameCount = process.frames_count
  let eventCount = process.in_events.size(process.in_events)
  var eventIndex = 0'u32
  var nextEventIndex = if eventCount > 0: 0'u32 else: frameCount
  var i = 0'u32
  while i < frameCount:
    while eventIndex < eventCount and nextEventIndex == i:
      let eventHeader = process.in_events.get(process.in_events, eventIndex)
      if eventHeader.time != i:
        nextEventIndex = eventHeader.time
        break

      # case eventHeader.`type`:
      # of CLAP_EVENT_PARAM_VALUE:
      #   let event = cast[clap_event_param_value_t](eventHeader)
      #   p.processParameterValueEvent(ParameterValueEvent(
      #     parameterId: event.param_id.int,
      #     note: event.note_id.int,
      #     port: event.port_index.int,
      #     channel: event.channel.int,
      #     key: event.key.int,
      #     value: event.value.float,
      #   ))
      # else:
      #   discard

      eventIndex += 1

      if eventIndex == eventCount:
        nextEventIndex = frameCount
        break

    p.processAudio(process.audio_inputs.addr, process.audio_outputs.addr, i.int, nextEventIndex.int)

    i = nextEventIndex

  return CLAP_PROCESS_CONTINUE

var audioPortsExtension = clap_plugin_audio_ports_t(
  count: proc(plugin: ptr clap_plugin_t, is_input: bool): uint32 {.cdecl.} =
    return 1

  , get: proc(plugin: ptr clap_plugin_t, index: uint32, is_input: bool, info: ptr clap_audio_port_info_t): bool {.cdecl.} =
    info.id = 0
    info.channel_count = 2
    info.flags = CLAP_AUDIO_PORT_IS_MAIN
    info.port_type = CLAP_PORT_STEREO
    info.in_place_pair = CLAP_INVALID_ID
    return true
)

proc get_extension(plugin: ptr clap_plugin_t, id: cstring): pointer {.cdecl.} =
  # if id == CLAP_EXT_TRACK_INFO:
  #   return audioPortsExtension.addr
  if id == CLAP_EXT_AUDIO_PORTS:
    return audioPortsExtension.addr
  return nil

proc on_main_thread(plugin: ptr clap_plugin_t) {.cdecl.} =
  discard

proc addPlugin*(T: typedesc,
                id: string,
                name: string,
                vendor = "",
                url = "",
                manualUrl = "",
                supportUrl = "",
                version = "",
                description = "",
                features: openArray[string] = []) =
  # var pluginFeatures = newSeq[cstring](features.len)
  # for i, feature in features:
  #   pluginFeatures[i] = feature.cstring
  # pluginFeatures[-1] = nil

  var info = ClapPluginInfo(
    descriptor: clap_plugin_descriptor_t(
      clap_version: clap_version_t(major: 1, minor: 1, revision: 7),
      id: id,
      name: name,
      vendor: vendor,
      url: url,
      manual_url: manualUrl,
      support_url: supportUrl,
      version: version,
      description: description,
      # features: pluginFeatures[0].addr,
      features: nil,
    ),
  )

  info.createInstance = proc(info: ClapPluginInfo): ptr clap_plugin_t =
    var p = create(clap_plugin_t)
    p.desc = info.descriptor.addr
    var data = T()
    GC_ref(data)
    p.plugin_data = cast[pointer](data)
    p.init = init
    p.destroy = destroy
    p.activate = activate
    p.deactivate = deactivate
    p.start_processing = start_processing
    p.stop_processing = stop_processing
    p.reset = reset
    p.process = process
    p.get_extension = get_extension
    p.on_main_thread = on_main_thread
    return p

  pluginInfo.add info