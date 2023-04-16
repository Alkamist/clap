import std/locks
import ./binding; export binding

type
  AudioBuffer* = clap_audio_buffer_t

template `[]`*(buffer: AudioBuffer, channel: auto): untyped =
  cast[ptr UncheckedArray[ptr UncheckedArray[cfloat]]](buffer.data32)[channel]

type
  PluginCreator = object
    descriptor: clap_plugin_descriptor_t
    createInstance: proc(): pointer

  ParameterInfo = object
    name*: string
    module*: string
    minValue*: float
    maxValue*: float
    defaultValue*: float

  Plugin* = ref object of RootObj
    sampleRate*: float
    parameterCount: int
    parameterInfo: seq[ParameterInfo]
    parameterValueMainThread: seq[float]
    parameterValueAudioThread: seq[float]
    parameterChangedMainThread: seq[bool]
    parameterChangedAudioThread: seq[bool]
    parameterLock: Lock

method init*(plugin: Plugin) {.base.} = discard
method processAudio*(plugin: Plugin, inputs, outputs: openArray[AudioBuffer], startFrame, endFrame: int) {.base.} = discard

proc parameter*(plugin: Plugin, id: int): float = plugin.parameterValueAudioThread[id]
proc parameter*(plugin: Plugin, id: enum): float = plugin.parameterValueAudioThread[id.int]
proc addParameter*(plugin: Plugin,
                   id: enum,
                   name: string,
                   minValue: float,
                   maxValue: float,
                   defaultValue: float,
                   module = "") =
  let idNumber = id.int
  let idCount = idNumber + 1

  if idCount > plugin.parameterCount:
    plugin.parameterCount = idCount

  if idCount > plugin.parameterInfo.len:
    plugin.parameterInfo.setLen(idCount)
    plugin.parameterValueMainThread.setLen(idCount)
    plugin.parameterValueAudioThread.setLen(idCount)
    plugin.parameterChangedMainThread.setLen(idCount)
    plugin.parameterChangedAudioThread.setLen(idCount)

  plugin.parameterInfo[idNumber] = ParameterInfo(
    name: name,
    module: module,
    minValue: minValue,
    maxValue: maxValue,
    defaultValue: defaultValue,
  )
  plugin.parameterValueMainThread[idNumber] = defaultValue
  plugin.parameterValueAudioThread[idNumber] = defaultValue
  plugin.parameterChangedMainThread[idNumber] = false
  plugin.parameterChangedAudioThread[idNumber] = false

proc syncMainThreadToAudioThread*(plugin: Plugin, outputEvents: ptr clap_output_events_t) =
  acquire(plugin.parameterLock)

  for i in 0 ..< plugin.parameterCount:
    if plugin.parameterChangedMainThread[i]:
      plugin.parameterValueAudioThread[i] = plugin.parameterValueMainThread[i]
      plugin.parameterChangedMainThread[i] = false

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
      event.value = plugin.parameterValueAudioThread[i]
      discard outputEvents.try_push(outputEvents, event.header.addr)

  release(plugin.parameterLock)

proc syncAudioThreadToMainThread*(plugin: Plugin) =
  acquire(plugin.parameterLock)

  for i in 0 ..< plugin.parameterCount:
    if plugin.parameterChangedAudioThread[i]:
      plugin.parameterValueMainThread[i] = plugin.parameterValueAudioThread[i]
      plugin.parameterChangedAudioThread[i] = false

  release(plugin.parameterLock)

var pluginCreators: seq[PluginCreator]

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
  pluginCreators.add PluginCreator(
    descriptor: clap_plugin_descriptor_t(
      id: id,
      name: name,
      vendor: vendor,
      url: url,
      manualUrl: manualUrl,
      supportUrl: supportUrl,
      version: version,
      description: description,
    ),
    createInstance: proc(): pointer =
      let instance = T()
      GcRef(instance)
      return cast[pointer](instance)
  )

proc plugin_init(plugin: ptr clap_plugin_t): bool {.cdecl.} =
  let p = cast[Plugin](plugin.plugin_data)
  initLock(p.parameterLock)
  p.init()
  return true

proc plugin_destroy(plugin: ptr clap_plugin_t) {.cdecl.} =
  let p = cast[Plugin](plugin.plugin_data)
  deinitLock(p.parameterLock)
  GcUnref(p)
  dealloc(plugin)

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
          p.parameterValueAudioThread[parameterId] = event.value
          p.parameterChangedAudioThread[parameterId] = true
          release(p.parameterLock)
        else:
          discard

      eventIndex += 1

      if eventIndex == eventCount:
        nextEventIndex = frameCount
        break

    p.processAudio(
      cast[ptr UncheckedArray[AudioBuffer]](process.audio_inputs).toOpenArray(0, process.audio_inputs_count.int),
      cast[ptr UncheckedArray[AudioBuffer]](process.audio_outputs).toOpenArray(0, process.audio_outputs_count.int),
      frame.int, nextEventIndex.int,
    )

    frame = nextEventIndex

  return CLAP_PROCESS_CONTINUE

var paramsExtension = clap_plugin_params_t(
  count: proc(plugin: ptr clap_plugin_t): uint32 {.cdecl.} =
    let p = cast[Plugin](plugin.plugin_data)
    return p.parameterCount.uint32

  , get_info: proc(plugin: ptr clap_plugin_t, param_index: uint32, param_info: ptr clap_param_info_t): bool {.cdecl.} =
    let p = cast[Plugin](plugin.plugin_data)
    let info = p.parameterInfo[param_index]

    zeroMem(param_info, sizeof(clap_param_info_t))
    param_info.id = param_index
    param_info.flags = CLAP_PARAM_IS_AUTOMATABLE
    param_info.min_value = info.minValue
    param_info.max_value = info.maxValue
    param_info.default_value = info.defaultValue

    for j, c in info.name:
      if j >= CLAP_NAME_SIZE:
        break
      param_info.name[j] = c

    return true

  , get_value: proc(plugin: ptr clap_plugin_t, param_id: clap_id, out_value: ptr cdouble): bool {.cdecl.} =
      let p = cast[Plugin](plugin.plugin_data)

      acquire(p.parameterLock)

      if p.parameterChangedMainThread[param_id]:
        out_value[] = p.parameterValueMainThread[param_id]
      else:
        out_value[] = p.parameterValueAudioThread[param_id]

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
        p.parameterValueAudioThread[parameterId] = event.value
        p.parameterChangedAudioThread[parameterId] = true
        release(p.parameterLock)
      else:
        discard
)

var stateExtension = clap_plugin_state_t(
  save: proc(plugin: ptr clap_plugin_t, stream: ptr clap_ostream_t): bool {.cdecl.} =
    let p = cast[Plugin](plugin.plugin_data)

    p.syncAudioThreadToMainThread()

    return sizeof(float) * p.parameterCount == stream.write(stream, p.parameterValueMainThread[0].addr, (sizeof(float) * p.parameterCount).uint64)

  , load: proc(plugin: ptr clap_plugin_t, stream: ptr clap_istream_t): bool {.cdecl.} =
    let p = cast[Plugin](plugin.plugin_data)

    acquire(p.parameterLock)

    let success = sizeof(float) * p.parameterCount == stream.read(stream, p.parameterValueMainThread[0].addr, (sizeof(float) * p.parameterCount).uint64)

    for i in 0 ..< p.parameterCount:
      p.parameterChangedMainThread[i] = true

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

var clapFactory = clap_plugin_factory_t(
  get_plugin_count: proc(factory: ptr clap_plugin_factory_t): uint32 {.cdecl.} =
    return pluginCreators.len.uint32

  , get_plugin_descriptor: proc(factory: ptr clap_plugin_factory_t, index: uint32): ptr clap_plugin_descriptor_t {.cdecl.} =
    return pluginCreators[index].descriptor.addr

  , create_plugin: proc(factory: ptr clap_plugin_factory_t, host: ptr clap_host_t, plugin_id: cstring): ptr clap_plugin_t {.cdecl.} =
    if not clap_version_is_compatible(host.clap_version):
      return nil

    for i in 0 ..< pluginCreators.len:
      if plugin_id == pluginCreators[i].descriptor.id:
        var clapPlugin = create(clap_plugin_t)
        clapPlugin.plugin_data = pluginCreators[i].createInstance()
        clapPlugin.desc = pluginCreators[i].descriptor.addr
        clapPlugin.init = plugin_init
        clapPlugin.destroy = plugin_destroy
        clapPlugin.activate = plugin_activate
        clapPlugin.deactivate = plugin_deactivate
        clapPlugin.start_processing = plugin_start_processing
        clapPlugin.stop_processing = plugin_stop_processing
        clapPlugin.reset = plugin_reset
        clapPlugin.process = plugin_process
        clapPlugin.get_extension = plugin_get_extension
        clapPlugin.on_main_thread = plugin_on_main_thread
        return clapPlugin
)

proc NimMain() {.importc.}

proc main_init(plugin_path: cstring): bool {.cdecl.} =
  NimMain()
  return true

proc main_deinit() {.cdecl.} =
  discard

proc main_get_factory(factory_id: cstring): pointer {.cdecl.} =
  if factory_id == CLAP_PLUGIN_FACTORY_ID:
    return clapFactory.addr

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

#if !defined(CLAP_ABI)
#   if defined _WIN32 || defined __CYGWIN__
#      define CLAP_ABI __cdecl
#   else
#      define CLAP_ABI
#   endif
#endif

typedef struct clap_version {
  uint32_t major;
  uint32_t minor;
  uint32_t revision;
} clap_version_t;

typedef struct clap_plugin_entry {
  clap_version_t clap_version;
  bool(CLAP_ABI *init)(const char *plugin_path);
  void(CLAP_ABI *deinit)(void);
  const void *(CLAP_ABI *get_factory)(const char *factory_id);
} clap_plugin_entry_t;

#define CLAP_VERSION_MAJOR 1
#define CLAP_VERSION_MINOR 1
#define CLAP_VERSION_REVISION 7
#define CLAP_VERSION_INIT { (uint32_t)CLAP_VERSION_MAJOR, (uint32_t)CLAP_VERSION_MINOR, (uint32_t)CLAP_VERSION_REVISION }

CLAP_EXPORT const clap_plugin_entry_t clap_entry = {
  .clap_version = CLAP_VERSION_INIT,
  .init = `main_init`,
  .deinit = `main_deinit`,
  .get_factory = `main_get_factory`,
};
""".}