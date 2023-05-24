{.experimental: "codeReordering".}

import std/options; export options
import std/tables; export tables
import std/typetraits
import std/parseutils
import std/strutils
import std/algorithm
import std/atomics
import clap

type
  MidiEvent* = object
    time*: int
    port*: int
    data*: array[3, uint8]

  ParameterEventKind* = enum
    Value
    Modulation

  ParameterEvent* = object
    id: int
    kind: ParameterEventKind
    note_id: int
    port: int
    channel: int
    key: int
    value: float

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

  AudioPlugin* = ref object of RootObj
    sampleRate*: float
    minFrameCount*: int
    maxFrameCount*: int
    latency*: int
    isActive*: bool
    clapPlugin*: clap_plugin_t
    clapHost*: ptr clap_host_t
    clapHostLog*: ptr clap_host_log_t
    clapHostLatency*: ptr clap_host_latency_t
    clapHostTimerSupport*: ptr clap_host_timer_support_t
    timerNameToId*: Table[string, clap_id]
    timerIdToProc*: Table[clap_id, proc(plugin: AudioPlugin)]
    # parameterValues*: seq[Atomic[float]]
    outputEvents*: seq[clap_event_midi_t]

proc millisecondsToSamples*(plugin: AudioPlugin, milliseconds: float): int =
  return int(plugin.sampleRate * milliseconds * 0.001)

# proc parameterCount*(plugin: AudioPlugin): int =
#   return plugin.parameterValues.len

# proc parameter*[T](plugin: AudioPlugin, id: T): float =
#   return plugin.parameterValues[int(id)].load()

# proc setParameter*[T](plugin: AudioPlugin, id: T, value: float) =
#   plugin.parameterValues[int(id)].store(value)

# proc resetParameterToDefault*[T](plugin: AudioPlugin, id: T) =
#   plugin.setParameter(id, plugin.dispatcher.parameterInfo[int(id)].defaultValue)

proc registerTimer*(plugin: AudioPlugin, name: string, periodMs: int, timerProc: proc(plugin: AudioPlugin)) =
  if plugin.clapHostTimerSupport == nil or
     plugin.clapHostTimerSupport.registerTimer == nil:
    return

  var id: clap_id
  discard plugin.clapHostTimerSupport.registerTimer(plugin.clapHost, uint32(periodMs), id.addr)
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

proc setLatency*(plugin: AudioPlugin, value: int) =
  plugin.latency = value

  if plugin.clapHostLatency == nil or
     plugin.clapHostLatency.changed == nil or
     plugin.clapHost.requestRestart == nil:
    return

  # Inform the host of the latency change
  plugin.clapHostLatency.changed(plugin.clapHost)
  if plugin.isActive:
    plugin.clapHost.requestRestart(plugin.clapHost)

proc sendMidiEvent*(plugin: AudioPlugin, event: MidiEvent) =
  plugin.outputEvents.add(clap_event_midi_t(
    header: clap_event_header_t(
      size: uint32(sizeof(clap_event_midi_t)),
      # after the bug in reaper gets fixed: time = uint32(event.time)
      time: uint32(event.time - plugin.latency),
      space_id: CLAP_CORE_EVENT_SPACE_ID,
      type: CLAP_EVENT_MIDI,
      flags: 0,
    ),
    port_index: uint16(event.port),
    data: event.data,
  ))


# ==============================================================================
# Implementation
# ==============================================================================


template writeStringToBuffer(str: string, buffer, length: untyped) =
  let strLen = str.len
  for i in 0 ..< int(length):
    if i < strLen:
      buffer[i] = elementType(buffer)(str[i])
    else:
      buffer[i] = elementType(buffer)(0)
      break

proc pluginInit[T](plugin: ptr clap_plugin_t): bool {.cdecl.} =
  mixin init
  let plugin = cast[T](plugin.plugin_data)

  # for i in 0 ..< plugin.parameterCount:
  #   plugin.resetParameterToDefault(i)

  # plugin.clap_host_log = cast(^Clap_Host_Log)(plugin.clap_host->get_extension(CLAP_EXT_LOG))
  plugin.clapHostTimerSupport = cast[ptr clap_host_timer_support_t](plugin.clapHost.get_extension(plugin.clapHost, CLAP_EXT_TIMER_SUPPORT))
  plugin.clapHostLatency = cast[ptr clap_host_latency_t](plugin.clapHost.get_extension(plugin.clapHost, CLAP_EXT_LATENCY))
  plugin.outputEvents = newSeqOfCap[clap_event_midi_t](16384)

  plugin.init()

  return true

proc pluginDestroy[T](plugin: ptr clap_plugin_t) {.cdecl.} =
  mixin destroy
  let plugin = cast[T](plugin.plugin_data)
  plugin.destroy()
  GcUnRef(plugin)

proc pluginActivate[T](plugin: ptr clap_plugin_t, sample_rate: float, min_frames_count, max_frames_count: uint32): bool {.cdecl.} =
  mixin activate
  let plugin = cast[T](plugin.plugin_data)

  plugin.sampleRate = sample_rate
  plugin.minFrameCount = int(min_frames_count)
  plugin.maxFrameCount = int(max_frames_count)
  plugin.isActive = true

  plugin.activate()

  return true

proc pluginDeactivate[T](plugin: ptr clap_plugin_t) {.cdecl.} =
  mixin deactivate
  let plugin = cast[T](plugin.plugin_data)
  plugin.isActive = false
  plugin.deactivate()

proc pluginStartProcessing(plugin: ptr clap_plugin_t): bool {.cdecl.} =
  return true

proc pluginStopProcessing(plugin: ptr clap_plugin_t) {.cdecl.} =
  discard

proc pluginReset[T](plugin: ptr clap_plugin_t) {.cdecl.} =
  mixin reset
  let plugin = cast[T](plugin.plugin_data)
  plugin.outputEvents.setLen(0)
  plugin.reset()

proc pluginProcess[T](plugin: ptr clap_plugin_t, process: ptr clap_process_t): clap_process_status {.cdecl.} =
  let plugin = cast[T](plugin.plugin_data)

  let frameCount = process.frames_count
  let eventCount = process.in_events.size(process.in_events)
  var eventIndex: uint32 = 0
  var nextEventIndex: uint32 = 0
  if eventCount == 0:
    nextEventIndex = frameCount

  var frame: uint32 = 0

  # plugin.dispatchTransportEvent(process.transport)

  while frame < frameCount:
    while eventIndex < eventCount and nextEventIndex == frame:
      var eventHeader = process.in_events.get(process.in_events, eventIndex)
      if eventHeader.time != frame:
        nextEventIndex = eventHeader.time
        break

      # if eventHeader.space_id == CLAP_CORE_EVENT_SPACE_ID:
      #   plugin.dispatchParameterEvent(eventHeader)
      #   plugin.dispatchMidiEvent(eventHeader)

      eventIndex += 1

      if eventIndex == eventCount:
        nextEventIndex = frameCount
        break

    # Audio processing will happen here eventually.

    frame = nextEventIndex

  # plugin.process(int(process.frames_count))

  # Sort and send output events, then clear the buffer.
  plugin.outputEvents.sort do (x, y: clap_event_midi_t) -> int:
    cmp(x.header.time, y.header.time)
  for event in plugin.outputEvents:
    var event = event
    discard process.out_events.try_push(process.out_events, cast[ptr clap_event_header_t](addr(event)))

  plugin.outputEvents.setLen(0)

  return CLAP_PROCESS_CONTINUE

proc pluginGetExtension(plugin: ptr clap_plugin_t, id: cstring): pointer {.cdecl.} =
  # if id == CLAP_EXT_NOTE_PORTS: return addr(clapExtensionNotePorts)
  if id == CLAP_EXT_LATENCY: return addr(clapExtensionLatency)
  # if id == CLAP_EXT_PARAMS: return addr(clapExtensionParameters)
  # if id == CLAP_EXT_TIMER_SUPPORT: return addr(clapExtensionTimer)
  # if id == CLAP_EXT_STATE: return addr(clapExtensionState)
  # if id == CLAP_EXT_GUI: return addr(clapExtensionGui)
  return nil

proc pluginOnMainThread(plugin: ptr clap_plugin_t) {.cdecl.} =
  discard

# var clapExtensionParameters = clap_plugin_params_t(
#   count: proc(plugin: ptr clap_plugin_t): uint32 {.cdecl.} =
#     let plugin = cast[T](plugin.plugin_data)
#     return uint32(plugin.parameterCount)
#   ,
#   get_info: proc(plugin: ptr clap_plugin_t, param_index: uint32, param_info: ptr clap_param_info_t): bool {.cdecl.} =
#     let plugin = cast[T](plugin.plugin_data)
#     if plugin.parameterCount == 0:
#       return false
#     let info = plugin.dispatcher.parameterInfo
#     param_info.id = uint32(info[param_index].id)
#     param_info.flags = info[param_index].flags.toClapParamInfoFlags()
#     writeStringToBuffer(info[param_index].name, param_info.name, CLAP_NAME_SIZE)
#     writeStringToBuffer(info[param_index].module, param_info.module, CLAP_PATH_SIZE)
#     param_info.minValue = info[param_index].minValue
#     param_info.maxValue = info[param_index].maxValue
#     param_info.defaultValue = info[param_index].defaultValue
#     return true
#   ,
#   get_value: proc(plugin: ptr clap_plugin_t, param_id: clap_id, out_value: ptr float): bool {.cdecl.} =
#     let plugin = cast[T](plugin.plugin_data)
#     if plugin.parameterCount == 0:
#       return false
#     out_value[] = plugin.parameter(param_id)
#     return true
#   ,
#   value_to_text: proc(plugin: ptr clap_plugin_t, param_id: clap_id, value: float, out_buffer: ptr UncheckedArray[char], out_buffer_capacity: uint32): bool {.cdecl.} =
#     let plugin = cast[T](plugin.plugin_data)
#     if plugin.parameterCount == 0:
#       return false
#     var valueStr = value.formatFloat(ffDecimal, 3)
#     writeStringToBuffer(valueStr, out_buffer, out_buffer_capacity)
#     return true
#   ,
#   text_to_value: proc(plugin: ptr clap_plugin_t, param_id: clap_id, param_value_text: cstring, out_value: ptr float): bool {.cdecl.} =
#     let plugin = cast[T](plugin.plugin_data)
#     if plugin.parameterCount == 0:
#       return false
#     var value: float
#     let res = parseutils.parseFloat($param_value_text, value)
#     if res != 0:
#       out_value[] = value
#       return true
#     else:
#       return false
#   ,
#   flush: proc(plugin: ptr clap_plugin_t, input: ptr clap_input_events_t, output: ptr clap_output_events_t) {.cdecl.} =
#     let plugin = cast[T](plugin.plugin_data)
#     let eventCount = input.size(input)
#     for i in 0 ..< eventCount:
#       let eventHeader = input.get(input, i)
#       plugin.dispatchParameterEvent(eventHeader)
#   ,
# )

# var clapExtensionLatency = clap_plugin_latency_t(
#   get: proc(plugin: ptr clap_plugin_t): uint32 {.cdecl.} =
#     let plugin = cast[T](plugin.plugin_data)
#     return uint32(max(0, plugin.latency))
#   ,
# )

# var clapExtensionNotePorts = clap_plugin_note_ports_t(
#   count: proc(plugin: ptr clap_plugin_t, is_input: bool): uint32 {.cdecl.} =
#     return 1
#   ,
#   get: proc(plugin: ptr clap_plugin_t, index: uint32, is_input: bool, info: ptr clap_note_port_info_t): bool {.cdecl.} =
#     info.id = 0
#     info.supported_dialects = CLAP_NOTE_DIALECT_MIDI
#     info.preferred_dialect = CLAP_NOTE_DIALECT_MIDI
#     writeStringToBuffer("MIDI Port 1", info.name, CLAP_NAME_SIZE)
#     return true
#   ,
# )

# var clapExtensionTimer = clap_plugin_timer_support_t(
#   on_timer: proc(plugin: ptr clap_plugin_t, timer_id: clap_id) {.cdecl.} =
#     let plugin = cast[T](plugin.plugin_data)
#     if plugin.timerIdToProc.hasKey(timer_id):
#       plugin.timerIdToProc[timerId](plugin)
#   ,
# )

# var clapExtensionState = clap_plugin_state_t(
#   save: proc(plugin: ptr clap_plugin_t, stream: ptr clap_ostream_t): bool {.cdecl.} =
#     let plugin = cast[T](plugin.plugin_data)

#     var preset = plugin.savePreset()

#     var writePtr = addr(preset[0])
#     var bytesToWrite = int64(preset.len)
#     while true:
#       var bytesWritten = stream.write(stream, writePtr, uint64(bytesToWrite))

#       # Success
#       if bytesWritten == bytesToWrite:
#         break

#       # An error happened
#       if bytesWritten <= 0 or bytesWritten > bytesToWrite:
#         return false

#       bytesToWrite -= bytesWritten
#       writePtr = cast[ptr char](cast[uint](writePtr) + cast[uint](bytesWritten))

#     return true
#   ,
#   load: proc(plugin: ptr clap_plugin_t, stream: ptr clap_istream_t): bool {.cdecl.} =
#     let plugin = cast[T](plugin.plugin_data)

#     var preset: seq[byte]

#     while true:
#       var dataByte: byte
#       var bytesRead = stream.read(stream, addr(dataByte), 1)

#       # Hit the end of the stream
#       if bytesRead == 0:
#         break

#       # Possibly more to read so keep going
#       if bytesRead == 1:
#         preset.add(dataByte)
#         continue

#       # An error happened
#       if bytesRead < 0:
#         return false

#     plugin.loadPreset()

#     return true
#   ,
# )

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
          get_extension: pluginGetExtension,
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

# proc fromBeatTime(time: clap_beat_time): float =
#   return int(time) / CLAP_BEATTIME_FACTOR

# proc fromSecTime(time: clap_sec_time): float =
#   return int(time) / CLAP_SECTIME_FACTOR

# proc toClapParamInfoFlags(flags: set[ParameterFlag]): clap_param_info_flags =
#   if IsStepped in flags: result = result or CLAP_PARAM_IS_STEPPED
#   if IsPeriodic in flags: result = result or CLAP_PARAM_IS_PERIODIC
#   if IsHidden in flags: result = result or CLAP_PARAM_IS_HIDDEN
#   if IsRead_Only in flags: result = result or CLAP_PARAM_IS_READ_ONLY
#   if IsBypass in flags: result = result or CLAP_PARAM_IS_BYPASS
#   if IsAutomatable in flags: result = result or CLAP_PARAM_IS_AUTOMATABLE
#   if IsAutomatablePerNote_Id in flags: result = result or CLAP_PARAM_IS_AUTOMATABLE_PER_NOTE_ID
#   if IsAutomatablePerKey in flags: result = result or CLAP_PARAM_IS_AUTOMATABLE_PER_KEY
#   if IsAutomatablePerChannel in flags: result = result or CLAP_PARAM_IS_AUTOMATABLE_PER_CHANNEL
#   if IsAutomatablePerPort in flags: result = result or CLAP_PARAM_IS_AUTOMATABLE_PER_PORT
#   if IsModulatable in flags: result = result or CLAP_PARAM_IS_MODULATABLE
#   if IsModulatablePerNoteId in flags: result = result or CLAP_PARAM_IS_MODULATABLE_PER_NOTE_ID
#   if IsModulatablePerKey in flags: result = result or CLAP_PARAM_IS_MODULATABLE_PER_KEY
#   if IsModulatablePerChannel in flags: result = result or CLAP_PARAM_IS_MODULATABLE_PER_CHANNEL
#   if IsModulatablePerPort in flags: result = result or CLAP_PARAM_IS_MODULATABLE_PER_PORT
#   if Requires_Process in flags: result = result or CLAP_PARAM_REQUIRES_PROCESS
#   return result

# proc dispatchParameterEvent(plugin: AudioPlugin, eventHeader: ptr clap_event_header_t) =
#   case eventHeader.`type`:
#   of CLAP_EVENT_PARAM_VALUE:
#     var clapEvent = cast[ptr clap_event_param_value_t](eventHeader)
#     plugin.setParameter(clapEvent.param_id, clapEvent.value)
#     if plugin.dispatcher.vtable.onParameterEvent != nil:
#       plugin.dispatcher.vtable.onParameterEvent(plugin, ParameterEvent(
#         id: int(clapEvent.param_id),
#         kind: Value,
#         note_id: int(clapEvent.note_id),
#         port: int(clapEvent.port_index),
#         channel: int(clapEvent.channel),
#         key: int(clapEvent.key),
#         value: clapEvent.value,
#       ))
#   else:
#     discard

# proc dispatchTransportEvent(plugin: AudioPlugin, clapEvent: ptr clap_event_transport_t) =
#   if clapEvent != nil:
#     var event = TransportEvent()

#     if (clapEvent.flags and CLAP_TRANSPORT_IS_PLAYING) != 0:
#       event.flags.incl(IsPlaying)

#     if (clapEvent.flags and CLAP_TRANSPORT_IS_RECORDING) != 0:
#       event.flags.incl(IsRecording)

#     if (clapEvent.flags and CLAP_TRANSPORT_IS_LOOP_ACTIVE) != 0:
#       event.flags.incl(LoopIsActive)

#     if (clapEvent.flags and CLAP_TRANSPORT_IS_WITHIN_PRE_ROLL) != 0:
#       event.flags.incl(IsWithinPreRoll)

#     if (clapEvent.flags and CLAP_TRANSPORT_HAS_TIME_SIGNATURE) != 0:
#       event.timeSignature = some(TimeSignature(
#         numerator: int(clapEvent.tsig_num),
#         denominator: int(clapEvent.tsig_denom),
#       ))

#     if (clapEvent.flags and CLAP_TRANSPORT_HAS_TEMPO) != 0:
#       event.tempo = some(clapEvent.tempo)
#       event.tempoIncrement = some(clapEvent.tempo_inc)

#     if (clapEvent.flags and CLAP_TRANSPORT_HAS_BEATS_TIMELINE) != 0:
#       event.songPositionBeats = some(fromBeatTime(clapEvent.song_pos_beats))
#       event.loopStartBeats = some(fromBeatTime(clapEvent.loop_start_beats))
#       event.loopEndBeats = some(fromBeatTime(clapEvent.loop_end_beats))
#       event.barStartBeats = some(fromBeatTime(clapEvent.bar_start))
#       event.barNumber = some(int(clapEvent.bar_number))

#     if (clapEvent.flags and CLAP_TRANSPORT_HAS_SECONDS_TIMELINE) != 0:
#       event.songPositionSeconds = some(fromSecTime(clapEvent.song_pos_seconds))
#       event.loopStartSeconds = some(fromSecTime(clapEvent.loop_start_seconds))
#       event.loopEndSeconds = some(fromSecTime(clapEvent.loop_end_seconds))

#     if plugin.dispatcher.vtable.onTransportEvent != nil:
#       plugin.dispatcher.vtable.onTransportEvent(plugin, event)

# proc dispatchMidiEvent(plugin: AudioPlugin, eventHeader: ptr clap_event_header_t) =
#   var clapEvent = cast[ptr clap_event_midi_t](eventHeader)
#   if plugin.dispatcher.vtable.onTransportEvent != nil:
#       plugin.dispatcher.vtable.onMidiEvent(plugin, MidiEvent(
#         time: int(event_header.time),
#         port: int(clap_event.port_index),
#         data: clap_event.data,
#       ))