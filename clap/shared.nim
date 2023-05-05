import std/tables; export tables
import std/locks; export locks
import std/typetraits; export typetraits
import ./binding

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
    info*: AudioPluginInfo
    sampleRate*: float
    latency*: int
    isActive*: bool
    clapHost*: ptr clap_host_t
    clapPlugin*: clap_plugin_t
    timerNameToIdTable*: Table[string, clap_id]
    timerIdToProcTable*: Table[clap_id, proc(plugin: AudioPlugin)]
    parameterLock*: locks.Lock
    mainThreadParameterValue*: seq[float]
    mainThreadParameterChanged*: seq[bool]
    audioThreadParameterValue*: seq[float]
    audioThreadParameterChanged*: seq[bool]
    outputMidiEvents*: seq[MidiEvent]

  AudioPluginInfo* = ref object
    onMidiEvent*: proc(plugin: AudioPlugin, event: MidiEvent)
    parameterInfo*: seq[ParameterInfo]
    clapDescriptor*: clap_plugin_descriptor_t
    createInstance*: proc(index: int, host: ptr clap_host_t): ptr clap_plugin_t

var pluginInfo*: seq[AudioPluginInfo]

proc getInstance*(plugin: ptr clap_plugin_t): AudioPlugin =
  return cast[AudioPlugin](plugin.plugin_data)

template writeStringToBuffer*(str: string, buffer, length: untyped) =
  let strLen = str.len
  for i in 0 ..< int(length):
    if i < strLen:
      buffer[i] = elementType(buffer)(str[i])
    else:
      buffer[i] = elementType(buffer)(0)