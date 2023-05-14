import std/options; export options
import std/tables; export tables
import std/typetraits
import reaper
import clap

type
  MidiEvent* = object
    time*: int
    port*: int
    data*: array[3, uint8]

  ParameterEventKind* = enum
    Value
    Modulation
    BeginUserChange
    EndUserChange

  ParameterEvent* = object
    index*: int
    case kind*: ParameterEventKind
    of Value, Modulation:
      noteId*: int
      port*: int
      channel*: int
      key*: int
      value*: float
    else:
      discard

  TimeSignature* = object
    numerator*: int
    denominator*: int

  TransportFlag* = enum
    IsPlaying
    IsRecording
    LoopIsActive
    IsWithinPreRoll

  TransportEvent* = object
    flags*: set[TransportFlag]

    songPositionSeconds*: Option[float]
    loopStartSeconds*: Option[float]
    loopEndSeconds*: Option[float]

    songPositionBeats*: Option[float]
    loopStartBeats*: Option[float]
    loopEndBeats*: Option[float]

    tempo*: Option[float]
    tempoIncrement*: Option[float]

    barStartBeats*: Option[float]
    barNumber*: Option[int]

    timeSignature*: Option[TimeSignature]

  ParameterFlag* = enum
    IsStepped
    IsPeriodic
    IsHidden
    IsReadOnly
    IsBypass
    IsAutomatable
    IsAutomatablePerNoteId
    IsAutomatablePerKey
    IsAutomatablePerChannel
    IsAutomatablePerPort
    IsModulatable
    IsModulatablePerNoteId
    IsModulatablePerKey
    IsModulatablePerChannel
    IsModulatablePerPort
    RequiresProcess

  ParameterInfo* = object
    id*: int
    name*: string
    minValue*: float
    maxValue*: float
    defaultValue*: float
    flags*: set[ParameterFlag]
    module*: string

  AudioPlugin* = ref object
    sampleRate*: float
    latency*: int
    isActive*: bool
    clapHost*: ptr clap_host_t
    clapHostLog*: ptr clap_host_log_t
    clapHostLatency*: ptr clap_host_latency_t
    clapHostTimerSupport*: ptr clap_host_timer_support_t
    clapPlugin*: clap_plugin_t
    timerNameToId*: Table[string, clap_id]
    timerIdToProc*: Table[clap_id, proc(plugin: AudioPlugin)]
    debugString*: string
    debugStringChanged*: bool

var clapDescriptor = clap_plugin_descriptor_t(
  clap_version: CLAP_VERSION_INIT,
  id: "com.alkamist.CssCorrector",
  name: "Css Corrector",
  vendor: "Alkamist Audio",
  url: "",
  manual_url: "",
  support_url: "",
  version: "0.1.0",
  description: "A MIDI timing corrector for Cinematic Studio Strings.",
)



proc setLatency*(plugin: AudioPlugin, value: int) =
  plugin.latency = value

  if plugin.clapHostLatency == nil or
     plugin.clapHostLatency.changed == nil or
     plugin.clapHost.requestRestart == nil:
      return

  # Inform the host of the latency change.
  plugin.clapHostLatency.changed(plugin.clapHost)
  if plugin.isActive:
    plugin.clapHost.requestRestart(plugin.clapHost)

proc registerTimer*(plugin: AudioPlugin, name: string, periodMs: int, timerProc: proc(plugin: AudioPlugin)) =
  if plugin.clapHostTimerSupport == nil or
     plugin.clapHostTimerSupport.registerTimer == nil:
    return

  var id: clap_id
  discard plugin.clapHostTimerSupport.registerTimer(plugin.clapHost, uint32(periodMs), addr(id))
  plugin.timerNameToId[name] = id
  plugin.timerIdToProc[id] = timerProc

proc unregisterTimer*(plugin: AudioPlugin, name: string) =
  if plugin.clapHostTimerSupport == nil or
     plugin.clapHostTimerSupport.unregisterTimer == nil:
    return

  if plugin.timerNameToId.hasKey(name):
    let id = plugin.timerNameToId[name]
    discard plugin.clapHostTimerSupport.unregisterTimer(plugin.clapHost, id)
    plugin.timerIdToProc[id] = nil

proc debug*(plugin: AudioPlugin, x: varargs[string, `$`]) =
  for i, msg in x:
    plugin.debugString.add(msg)
    if i + 1 < x.len:
      plugin.debugString.add(" ")
  plugin.debugString.add("\n")
  plugin.debugStringChanged = true







proc onActivate*(plugin: AudioPlugin) =
  plugin.registerTimer("DebugTimer", 0, proc(plugin: AudioPlugin) =
    if plugin.debugStringChanged:
      reaper.showConsoleMsg(cstring(plugin.debugString))
      plugin.debugString.setLen(0)
      plugin.debugStringChanged = false
  )

proc onDeactivate*(plugin: AudioPlugin) =
  plugin.unregisterTimer("DebugTimer")

proc onReset*(plugin: AudioPlugin) =
  discard

proc onMidiEvent*(plugin: AudioPlugin, event: MidiEvent) =
  plugin.debug(event)















# ============================================================================================
# Implementation
# ============================================================================================

proc getInstance(plugin: ptr clap_plugin_t): AudioPlugin =
  return cast[AudioPlugin](plugin.plugin_data)

template writeStringToBuffer(str: string, buffer, length: untyped) =
  let strLen = str.len
  for i in 0 ..< int(length):
    if i < strLen:
      buffer[i] = elementType(buffer)(str[i])
    else:
      buffer[i] = elementType(buffer)(0)

# ============================================================================================
# Extensions
# ============================================================================================

var latencyExtension = clap_plugin_latency_t(
  get: proc(plugin: ptr clap_plugin_t): uint32 {.cdecl.} =
    let plugin = plugin.getInstance()
    return uint32(plugin.latency)
  ,
)

var timerExtension = clap_plugin_timer_support_t(
  on_timer: proc(plugin: ptr clap_plugin_t, timer_id: clap_id) {.cdecl.} =
    let plugin = plugin.getInstance()
    if plugin.timerIdToProc.hasKey(timer_id):
      plugin.timerIdToProc[timerId](plugin)
  ,
)

var notePortsExtension = clap_plugin_note_ports_t(
  count: proc(plugin: ptr clap_plugin_t, is_input: bool): uint32 {.cdecl.} =
    return 1
  ,
  get: proc(plugin: ptr clap_plugin_t, index: uint32, is_input: bool, info: ptr clap_note_port_info_t): bool {.cdecl.} =
    info.id = 0
    info.supported_dialects = CLAP_NOTE_DIALECT_MIDI
    info.preferred_dialect = CLAP_NOTE_DIALECT_MIDI
    writeStringToBuffer("MIDI Port 1", info.name, CLAP_NAME_SIZE)
    return true
  ,
)

# ============================================================================================
# Plugin
# ============================================================================================

proc pluginInit(plugin: ptr clap_plugin_t): bool {.cdecl.} =
  let plugin = plugin.getInstance()
  plugin.clapHostLog = cast[ptr clap_host_log_t](plugin.clapHost.get_extension(plugin.clapHost, CLAP_EXT_LOG))
  plugin.clapHostLatency = cast[ptr clap_host_latency_t](plugin.clapHost.get_extension(plugin.clapHost, CLAP_EXT_LATENCY))
  plugin.clapHostTimerSupport = cast[ptr clap_host_timer_support_t](plugin.clapHost.get_extension(plugin.clapHost, CLAP_EXT_TIMER_SUPPORT))
  return true

proc pluginDestroy(plugin: ptr clap_plugin_t) {.cdecl.} =
  let plugin = plugin.getInstance()
  GcUnref(plugin)

proc pluginActivate(plugin: ptr clap_plugin_t, sample_rate: cdouble, min_frames_count, max_frames_count: uint32): bool {.cdecl.} =
  let plugin = plugin.getInstance()
  plugin.isActive = true
  plugin.sampleRate = sampleRate
  plugin.onActivate()
  return true

proc pluginDeactivate(plugin: ptr clap_plugin_t) {.cdecl.} =
  let plugin = plugin.getInstance()
  plugin.onDeactivate()
  plugin.isActive = false

proc pluginStartProcessing(plugin: ptr clap_plugin_t): bool {.cdecl.} =
  return true

proc pluginStopProcessing(plugin: ptr clap_plugin_t) {.cdecl.} =
  discard

proc pluginReset(plugin: ptr clap_plugin_t) {.cdecl.} =
  let plugin = plugin.getInstance()
  plugin.onReset()

proc pluginProcess(plugin: ptr clap_plugin_t, process: ptr clap_process_t): clap_process_status {.cdecl.} =
  let plugin = plugin.getInstance()

  let frameCount = process.frames_count
  let eventCount = process.in_events.size(process.in_events)
  var eventIndex = 0'u32
  var nextEventIndex = if eventCount > 0: 0'u32 else: frameCount
  var frame = 0'u32

  while frame < frameCount:
    while eventIndex < eventCount and nextEventIndex == frame:
      let eventHeader = process.in_events.get(process.in_events, eventIndex)
      if eventHeader.time != frame:
        nextEventIndex = eventHeader.time
        break

      if eventHeader.space_id == CLAP_CORE_EVENT_SPACE_ID:
        case eventHeader.`type`:
      #   of CLAP_EVENT_PARAM_VALUE:
      #     let event = cast[ptr clap_event_param_value_t](eventHeader)
      #     plugin.handleParameterValueEvent(event)

        of CLAP_EVENT_MIDI:
          let event = cast[ptr clap_event_midi_t](eventHeader)
          plugin.onMidiEvent(MidiEvent(
            time: int(eventHeader.time),
            port: int(event.portIndex),
            data: event.data,
          ))

        else:
          discard

      eventIndex += 1

      if eventIndex == eventCount:
        nextEventIndex = frameCount
        break

    frame = nextEventIndex

  return CLAP_PROCESS_CONTINUE

proc pluginOnMainThread(plugin: ptr clap_plugin_t) {.cdecl.} =
  discard

proc pluginGetExtension(plugin: ptr clap_plugin_t, id: cstring): pointer {.cdecl.} =
  # if id == CLAP_EXT_GUI: return addr(guiExtension)
  if id == CLAP_EXT_LATENCY: return addr(latencyExtension)
  if id == CLAP_EXT_NOTE_PORTS: return addr(noteportsExtension)
  # if id == CLAP_EXT_PARAMS: return addr(parametersExtension)
  if id == CLAP_EXT_TIMER_SUPPORT: return addr(timerExtension)
  # if id == CLAP_EXT_STATE: return addr(stateExtension)
  return nil

# ============================================================================================
# Entry
# ============================================================================================

proc createInstance(host: ptr clap_host_t): ptr clap_plugin_t =
    let plugin = AudioPlugin()
    GcRef(plugin)
    plugin.clapHost = host
    plugin.clapPlugin = clap_plugin_t(
      desc: addr(clapDescriptor),
      pluginData: cast[pointer](plugin),
      init: pluginInit,
      destroy: pluginDestroy,
      activate: pluginActivate,
      deactivate: pluginDeactivate,
      startProcessing: pluginStartProcessing,
      stopProcessing: pluginStopProcessing,
      reset: pluginReset,
      process: pluginProcess,
      getExtension: pluginGetExtension,
      onMainThread: pluginOnMainThread,
    )
    return addr(plugin.clapPlugin)

var clapFactory = clap_plugin_factory_t(
  get_plugin_count: proc(factory: ptr clap_plugin_factory_t): uint32 {.cdecl.} =
    return 1
  ,
  get_plugin_descriptor: proc(factory: ptr clap_plugin_factory_t, index: uint32): ptr clap_plugin_descriptor_t {.cdecl.} =
    return addr(clapDescriptor)
  ,
  create_plugin: proc(factory: ptr clap_plugin_factory_t, host: ptr clap_host_t, plugin_id: cstring): ptr clap_plugin_t {.cdecl.} =
    if not clap_version_is_compatible(host.clap_version):
      return nil

    var reaperPluginInfo = cast[ptr reaper_plugin_info_t](host.get_extension(host, "cockos.reaper_extension"))
    reaperPluginInfo.loadReaperFunctions()

    if pluginId == clapDescriptor.id:
      return createInstance(host)
)

proc NimMain() {.importc.}

proc mainInit(plugin_path: cstring): bool {.cdecl.} =
  NimMain()
  return true

proc mainDeinit() {.cdecl.} =
  discard

proc mainGetFactory(factoryId: cstring): pointer {.cdecl.} =
  if factoryId == CLAP_PLUGIN_FACTORY_ID:
    return addr(clapFactory)

{.emit: """/*VARSECTION*/
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

CLAP_EXPORT const `clap_plugin_entry_t` clap_entry = {
  .clap_version = {1, 1, 8},
  .init = `mainInit`,
  .deinit = `mainDeinit`,
  .get_factory = `mainGetFactory`,
};
""".}