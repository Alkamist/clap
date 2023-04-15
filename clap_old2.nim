# import std/strutils
import std/locks
import ./binding

type
  HostAudioBuffer* = ptr UncheckedArray[clap_audio_buffer_t]

  Parameter* = object
    name*: string
    module*: string
    minValue*: float
    maxValue*: float
    defaultValue*: float
    value*: float # Audio thread
    valueChanged*: bool
    mainThreadValue*: float
    mainThreadValueChanged*: bool

  Plugin* = ref object of RootObj
    sampleRate*: float
    parameters*: seq[Parameter]
    parameterLock: Lock

  PluginInfo = ref object
    descriptor: clap_plugin_descriptor_t
    createInstance: proc(info: PluginInfo): ptr clap_plugin_t

method init*(plugin: Plugin) {.base.} = discard
method processAudio*(plugin: Plugin, inputs, outputs: HostAudioBuffer, start, finish: int) {.base.} = discard

var pluginInfo: seq[PluginInfo]

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

proc main_init(plugin_path: cstring): bool {.cdecl.} =
  NimMain()
  return true

proc main_deinit() {.cdecl.} =
  discard

proc main_get_factory(factory_id: cstring): pointer {.cdecl.} =
  if factory_id == CLAP_PLUGIN_FACTORY_ID:
    return clapPluginFactory.addr

{.emit: """
#if !defined(CLAP_EXPORT)
#   if defined _WIN32 || defined __CYGWIN__
#      ifdef __GNUC__
#         define CLAP_EXPORT __attribute__((dllexport))
#      else
#         define CLAP_EXPORT __declspec(dllexport)
#      endif
#   else
#      if __GNUC__ >= 4 || defined(__clang__)
#         define CLAP_EXPORT __attribute__((visibility("default")))
#      else
#         define CLAP_EXPORT
#      endif
#   endif
#endif
CLAP_EXPORT const clap_plugin_entry_t clap_entry = {
  .clap_version = CLAP_VERSION_INIT,
  .init = `main_init`,
  .deinit = `main_deinit`,
  .get_factory = `main_get_factory`,
};
""".}

proc syncMainThreadToAudioThread(plugin: Plugin, outputEvents: ptr clap_output_events_t) =
  acquire(plugin.parameterLock)

  for i in 0 ..< plugin.parameters.len:
    if plugin.parameters[i].mainThreadValueChanged:
      plugin.parameters[i].value = plugin.parameters[i].mainThreadValue
      plugin.parameters[i].mainThreadValueChanged = false

      var event = clap_event_param_value_t()
      event.header.size = sizeof(event).uint32
      event.header.time = 0
      event.header.space_id = CLAP_CORE_EVENT_SPACE_ID
      event.header.`type` = CLAP_EVENT_PARAM_VALUE
      event.header.flags = 0
      event.param_id = i.clap_id
      event.cookie = nil
      event.note_id = -1
      event.port_index = -1
      event.channel = -1
      event.key = -1
      event.value = plugin.parameters[i].value
      discard outputEvents.try_push(outputEvents, event.header.addr)

  release(plugin.parameterLock)

proc syncAudioThreadToMainThread(plugin: Plugin) =
  acquire(plugin.parameterLock)

  for i in 0 ..< plugin.parameters.len:
    if plugin.parameters[i].valueChanged:
      plugin.parameters[i].mainThreadValue = plugin.parameters[i].value
      plugin.parameters[i].valueChanged = false

  release(plugin.parameterLock)

proc plugin_init(plugin: ptr clap_plugin_t): bool {.cdecl.} =
  let p = cast[Plugin](plugin.plugin_data)
  initLock(p.parameterLock)
  p.init()
  return true

proc plugin_destroy(plugin: ptr clap_plugin_t) {.cdecl.} =
  let p = cast[Plugin](plugin.plugin_data)
  deinitLock(p.parameterLock)
  GC_unref(p)
  dealloc(plugin)
  discard

proc plugin_activate(plugin: ptr clap_plugin_t, sample_rate: cdouble, min_frames_count, max_frames_count: uint32): bool {.cdecl.} =
  let p = cast[Plugin](plugin.plugin_data)
  p.sampleRate = sample_rate
  return true

proc plugin_deactivate(plugin: ptr clap_plugin_t) {.cdecl.} =
  discard

proc plugin_start_processing(plugin: ptr clap_plugin_t): bool {.cdecl.} =
  return true

proc plugin_stop_processing(plugin: ptr clap_plugin_t) {.cdecl.} =
  discard

proc plugin_reset(plugin: ptr clap_plugin_t) {.cdecl.} =
  discard

proc plugin_process(plugin: ptr clap_plugin_t, process: ptr clap_process_t): clap_process_status {.cdecl.} =
  let p = cast[Plugin](plugin.plugin_data)

  let frameCount = process.frames_count
  let eventCount = process.in_events.size(process.in_events)
  var eventIndex = 0'u32
  var nextEventIndex = if eventCount > 0: 0'u32 else: frameCount
  var frame = 0'u32

  p.syncMainThreadToAudioThread(process.out_events)

  while frame < frameCount:
    while eventIndex < eventCount and nextEventIndex == frame:
      let eventHeader = process.in_events.get(process.in_events, eventIndex)
      if eventHeader.time != frame:
        nextEventIndex = eventHeader.time
        break

      if eventHeader.space_id == CLAP_CORE_EVENT_SPACE_ID:
        case eventHeader.`type`:
        of CLAP_EVENT_PARAM_VALUE:
          let event = cast[ptr clap_event_param_value_t](eventHeader)
          let parameterId = event.param_id
          acquire(p.parameterLock)
          p.parameters[parameterId].value = event.value
          p.parameters[parameterId].valueChanged = true
          release(p.parameterLock)
        else:
          discard

      eventIndex += 1

      if eventIndex == eventCount:
        nextEventIndex = frameCount
        break

    # p.processAudio(process.audio_inputs.addr, process.audio_outputs.addr, frame.int, nextEventIndex.int)

    frame = nextEventIndex

  return CLAP_PROCESS_CONTINUE

var paramsExtension = clap_plugin_params_t(
  count: proc(plugin: ptr clap_plugin_t): uint32 {.cdecl.} =
    let p = cast[Plugin](plugin.plugin_data)
    return p.parameters.len.uint32

  , get_info: proc(plugin: ptr clap_plugin_t, param_index: uint32, param_info: ptr clap_param_info_t): bool {.cdecl.} =
    let p = cast[Plugin](plugin.plugin_data)
    let param = p.parameters[param_index]

    zeroMem(param_info, sizeof(clap_param_info_t))
    param_info.id = param_index
    param_info.flags = CLAP_PARAM_IS_AUTOMATABLE
    param_info.min_value = param.minValue
    param_info.max_value = param.maxValue
    param_info.default_value = param.defaultValue

    for j, c in param.name:
      if j >= CLAP_NAME_SIZE:
        break
      param_info.name[j] = c

    return true

  , get_value: proc(plugin: ptr clap_plugin_t, param_id: clap_id, out_value: ptr cdouble): bool {.cdecl.} =
      let p = cast[Plugin](plugin.plugin_data)

      acquire(p.parameterLock)

      if p.parameters[param_id].mainThreadValueChanged:
        out_value[] = p.parameters[param_id].mainThreadValue
      else:
        out_value[] = p.parameters[param_id].value

      release(p.parameterLock)

      return true

  , value_to_text: proc(plugin: ptr clap_plugin_t, param_id: clap_id, value: cdouble, out_buffer: ptr UncheckedArray[char], out_buffer_capacity: uint32): bool {.cdecl.} =
      out_buffer[0] = '1'
      out_buffer[1] = '\0'
      # let outputStr = value.formatFloat(ffDecimal, -1).cstring

      # for j, c in outputStr:
      #   if j.uint32 >= out_buffer_capacity:
      #     break
      #   out_buffer[j] = outputStr[j]

      return true

  , text_to_value: proc(plugin: ptr clap_plugin_t, param_id: clap_id, param_value_text: cstring, out_value: ptr cdouble): bool {.cdecl.} =
    return false

  , flush: proc(plugin: ptr clap_plugin_t, `in`: ptr clap_input_events_t, `out`: ptr clap_output_events_t) {.cdecl.} =
    let p = cast[Plugin](plugin.plugin_data)
    let eventCount = `in`.size(`in`)

    p.syncMainThreadToAudioThread(`out`)

    for eventIndex in 0 ..< eventCount:
      let eventHeader = `in`.get(`in`, eventIndex)
      case eventHeader.`type`:
      of CLAP_EVENT_PARAM_VALUE:
        let event = cast[ptr clap_event_param_value_t](eventHeader)
        let parameterId = event.param_id
        acquire(p.parameterLock)
        p.parameters[parameterId].value = event.value
        p.parameters[parameterId].valueChanged = true
        release(p.parameterLock)
      else:
        discard
)

var stateExtension = clap_plugin_state_t(
  save: proc(plugin: ptr clap_plugin_t, stream: ptr clap_ostream_t): bool {.cdecl.} =
    let p = cast[Plugin](plugin.plugin_data)

    p.syncAudioThreadToMainThread()

    var values = newSeq[float](p.parameters.len)
    for i, param in p.parameters:
      values[i] = param.mainThreadValue

    return sizeof(float) * p.parameters.len == stream.write(stream, values[0].addr, (sizeof(float) * p.parameters.len).uint64)

  , load: proc(plugin: ptr clap_plugin_t, stream: ptr clap_istream_t): bool {.cdecl.} =
    let p = cast[Plugin](plugin.plugin_data)

    acquire(p.parameterLock)

    var values = newSeq[float](p.parameters.len)

    let success = sizeof(float) * p.parameters.len == stream.read(stream, values[0].addr, (sizeof(float) * p.parameters.len).uint64)

    for i in 0 ..< p.parameters.len:
      p.parameters[i].mainThreadValue = values[i]
      p.parameters[i].mainThreadValueChanged = true

    release(p.parameterLock)

    return success
)

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

proc plugin_get_extension(plugin: ptr clap_plugin_t, id: cstring): pointer {.cdecl.} =
  if id == CLAP_EXT_AUDIO_PORTS: return audioPortsExtension.addr
  if id == CLAP_EXT_PARAMS: return paramsExtension.addr
  if id == CLAP_EXT_STATE: return stateExtension.addr
  return nil

proc plugin_on_main_thread(plugin: ptr clap_plugin_t) {.cdecl.} =
  discard

proc addParameter*(plugin: Plugin,
                   name: string,
                   module: string,
                   minValue: float,
                   maxValue: float,
                   defaultValue: float) =
  plugin.parameters.add Parameter(
    name: name,
    module: module,
    minValue: minValue,
    maxValue: maxValue,
    defaultValue: defaultValue,
    value: defaultValue,
    valueChanged: false,
    mainThreadValue: defaultValue,
    mainThreadValueChanged: false,
  )

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

  var info = PluginInfo(
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

  info.createInstance = proc(info: PluginInfo): ptr clap_plugin_t =
    var p = create(clap_plugin_t)
    p.desc = info.descriptor.addr
    var data = T()
    GC_ref(data)
    p.plugin_data = cast[pointer](data)
    p.init = plugin_init
    p.destroy = plugin_destroy
    p.activate = plugin_activate
    p.deactivate = plugin_deactivate
    p.start_processing = plugin_start_processing
    p.stop_processing = plugin_stop_processing
    p.reset = plugin_reset
    p.process = plugin_process
    p.get_extension = plugin_get_extension
    p.on_main_thread = plugin_on_main_thread
    return p

  pluginInfo.add info