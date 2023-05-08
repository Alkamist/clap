import std/tables; export tables
import std/locks; export locks
import std/typetraits; export typetraits
import ./binding

# =======================================================================================
# Types
# =======================================================================================

type
  MidiEvent* = object
    time*: int
    port*: int
    data*: array[3, uint8]

  ParamInfoFlags* = enum
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
    flags*: set[ParamInfoFlags]
    module*: string

  AudioPlugin* = ref object of RootObj
    dispatcher*: AudioPluginDispatcher
    sampleRate*: float
    latency*: int
    isActive*: bool
    clapHost*: ptr clap_host_t
    clapHostLog*: ptr clap_host_log_t
    clapHostLatency*: ptr clap_host_latency_t
    clapHostTimerSupport*: ptr clap_host_timer_support_t
    clapPlugin*: clap_plugin_t
    timerNameToIdTable*: Table[string, clap_id]
    timerIdToProcTable*: Table[clap_id, proc(plugin: AudioPlugin)]
    parameterLock*: locks.Lock
    mainThreadParameterValue*: seq[float]
    mainThreadParameterChanged*: seq[bool]
    audioThreadParameterValue*: seq[float]
    audioThreadParameterChanged*: seq[bool]
    outputMidiEvents*: seq[MidiEvent]

  AudioPluginDispatcher* = ref object
    onMidiEvent*: proc(plugin: AudioPlugin, event: MidiEvent)
    parameterInfo*: seq[ParameterInfo]
    clapDescriptor*: clap_plugin_descriptor_t
    createInstance*: proc(index: int, host: ptr clap_host_t): ptr clap_plugin_t

# =======================================================================================
# Globals
# =======================================================================================

var pluginDispatchers*: seq[AudioPluginDispatcher]

# =======================================================================================
# Utility
# =======================================================================================

proc getInstance*(plugin: ptr clap_plugin_t): AudioPlugin =
  return cast[AudioPlugin](plugin.plugin_data)

template writeStringToBuffer*(str: string, buffer, length: untyped) =
  let strLen = str.len
  for i in 0 ..< int(length):
    if i < strLen:
      buffer[i] = elementType(buffer)(str[i])
    else:
      buffer[i] = elementType(buffer)(0)

# =======================================================================================
# Log
# =======================================================================================

proc debug*(instance: AudioPlugin, msg: string) =
  if instance.clapHostLog == nil or
     instance.clapHostLog.log == nil:
    return
  instance.clapHostLog.log(instance.clapHost, CLAP_LOG_DEBUG, cstring(msg))

# =======================================================================================
# Parameters
# =======================================================================================

proc parameter*(instance: AudioPlugin, id: enum): float =
  instance.audioThreadParameterValue(int(id))

proc parameterCount*(instance: AudioPlugin): int =
  return instance.dispatcher.parameterInfo.len

proc syncParametersMainThreadToAudioThread*(instance: AudioPlugin, outputEvents: ptr clap_output_events_t) =
  instance.parameterLock.acquire()
  for i in 0 ..< instance.parameterCount:
    if instance.mainThreadParameterChanged[i]:
      instance.audioThreadParameterValue[i] = instance.mainThreadParameterValue[i]
      instance.mainThreadParameterChanged[i] = false
      var event = clap_event_param_value_t()
      event.header.size = uint32(sizeof(event))
      event.header.time = 0
      event.header.spaceId = CLAP_CORE_EVENT_SPACE_ID
      event.header.`type` = CLAP_EVENT_PARAM_VALUE
      event.header.flags = 0
      event.paramId = clap_id(i)
      event.cookie = nil
      event.noteId = -1
      event.portIndex = -1
      event.channel = -1
      event.key = -1
      event.value = instance.audioThreadParameterValue[i]
      discard outputEvents.try_push(outputEvents, addr(event.header))
  instance.parameterLock.release()

proc syncParametersAudioThreadToMainThread*(instance: AudioPlugin) =
  instance.parameterLock.acquire()
  for i in 0 ..< instance.parameterCount:
    if instance.audioThreadParameterChanged[i]:
      instance.mainThreadParameterValue[i] = instance.audioThreadParameterValue[i]
      instance.audioThreadParameterChanged[i] = false
  instance.parameterLock.release()

proc handleParameterValueEvent*(instance: AudioPlugin, event: ptr clap_event_param_value_t) =
  let id = event.param_id
  instance.parameterLock.acquire()
  instance.audioThreadParameterValue[id] = event.value
  instance.audioThreadParameterChanged[id] = true
  instance.parameterLock.release()

# =======================================================================================
# Timer
# =======================================================================================

proc registerTimer*(instance: AudioPlugin, name: string, periodMs: int, timerProc: proc(plugin: AudioPlugin)) =
  if instance.clapHostTimerSupport == nil or
     instance.clapHostTimerSupport.registerTimer == nil:
    return

  var id: clap_id
  discard instance.clapHostTimerSupport.registerTimer(instance.clapHost, uint32(periodMs), id.addr)
  instance.timerNameToIdTable[name] = id
  instance.timerIdToProcTable[id] = timerProc

proc unregisterTimer*(instance: AudioPlugin, name: string) =
  if instance.clapHostTimerSupport == nil or
     instance.clapHostTimerSupport.unregisterTimer == nil:
    return

  if instance.timerNameToIdTable.hasKey(name):
    let id = instance.timerNameToIdTable[name]
    discard instance.clapHostTimerSupport.unregisterTimer(instance.clapHost, id)
    instance.timerIdToProcTable[id] = nil

# =======================================================================================
# Latency
# =======================================================================================

proc setLatency*(instance: AudioPlugin, value: int) =
  instance.latency = value

  if instance.clapHostLatency == nil or
     instance.clapHostLatency.changed == nil or
     instance.clapHost.requestRestart == nil:
      return

  # Inform the host of the latency change.
  instance.clapHostLatency.changed(instance.clapHost)
  if instance.isActive:
    instance.clapHost.requestRestart(instance.clapHost)