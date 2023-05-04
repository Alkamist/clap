{.experimental: "overloadableEnums".}
{.experimental: "codeReordering".}

import std/locks
import std/tables
import std/parseutils
import std/strutils
import std/typetraits
import ./binding as clap

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

  AudioPluginInstance* = ref object
    sampleRate*: float
    latency*: int
    parameterCount*: int
    parameterInfo*: seq[ParameterInfo]
    isActive: bool
    clapHost: ptr clap.Host
    clapPlugin: clap.Plugin
    timerNameToIdTable: Table[string, clap.Id]
    timerIdToProcTable: Table[clap.Id, proc(plugin: AudioPluginInstance)]
    parameterLock: locks.Lock
    mainThreadParameterValue: seq[float]
    mainThreadParameterChanged: seq[bool]
    audioThreadParameterValue: seq[float]
    audioThreadParameterChanged: seq[bool]

  AudioPlugin* = ref object
    onMidiEvent*: proc(plugin: AudioPluginInstance, event: MidiEvent)
    clapDescriptor: clap.PluginDescriptor

var audioPlugins: seq[AudioPlugin]

# ===================================================================================================
# Audio Plugin
# ===================================================================================================


proc new*(T: type AudioPlugin,
          id: string,
          name: string,
          vendor: string,
          url: string,
          manualUrl: string,
          supportUrl: string,
          version: string,
          description: string): AudioPlugin =
  result = AudioPlugin()
  result.clapDescriptor = clap.PluginDescriptor(
    id: id,
    name: name,
    vendor: vendor,
    url: url,
    manualUrl: manualUrl,
    supportUrl: supportUrl,
    version: version,
    description: description,
  )
  audioPlugins.add(result)

proc addParameter*(plugin: AudioPlugin,
                   id: enum,
                   name: string,
                   minValue: float,
                   maxValue: float,
                   defaultValue: float,
                   flags: set[ParamInfoFlags],
                   module = "") =
  let idInt = int(id)
  if plugin.parameterCount < idInt + 1:
    plugin.parameterCount = idInt + 1
    plugin.parameterInfo.setLen(plugin.parameterCount)
    plugin.mainThreadParameterValue.setLen(plugin.parameterCount)
    plugin.mainThreadParameterChanged.setLen(plugin.parameterCount)
    plugin.audioThreadParameterValue.setLen(plugin.parameterCount)
    plugin.audioThreadParameterChanged.setLen(plugin.parameterCount)
  plugin.mainThreadParameterValue[idInt] = defaultValue
  plugin.audioThreadParameterValue[idInt] = defaultValue
  plugin.parameterInfo[idInt] = ParameterInfo(
    id: idInt,
    name: name,
    minValue: minValue,
    maxValue: maxValue,
    defaultValue: defaultValue,
    flags: flags,
    module: module,
  )


# ===================================================================================================
# Utility
# ===================================================================================================


template writeTo(str: string, buffer, length: untyped) =
  let strLen = str.len
  for i in 0 ..< int(length):
    if i < strLen:
      buffer[i] = elementType(buffer)(str[i])
    else:
      buffer[i] = elementType(buffer)(0)


# ===================================================================================================
# Clap Plugin
# ===================================================================================================


proc getPluginInstance(clapPlugin: ptr clap.Plugin): AudioPluginInstance =
  return cast[AudioPluginInstance](clapPlugin.pluginData)

proc pluginInit(clapPlugin: ptr clap.Plugin): bool {.cdecl.} =
  let plugin = clapPlugin.getPluginInstance()
  plugin.parameterLock.initLock()
  for i in 0 ..< plugin.parameterCount:
    plugin.mainThreadParameterValue[i] = plugin.parameterInfo[i].defaultValue
    plugin.audioThreadParameterValue[i] = plugin.parameterInfo[i].defaultValue
  return true

proc pluginDestroy(clapPlugin: ptr clap.Plugin) {.cdecl.} =
  let plugin = clapPlugin.getPluginInstance()
  plugin.parameterLock.deinitLock()
  GcUnref(plugin)

proc pluginActivate(clapPlugin: ptr clap.Plugin, sampleRate: float64, minFramesCount, maxFramesCount: uint32): bool {.cdecl.} =
  let plugin = clapPlugin.getPluginInstance()
  plugin.isActive = true
  plugin.sampleRate = sampleRate
  return true

proc pluginDeactivate(clapPlugin: ptr clap.Plugin) {.cdecl.} =
  let plugin = clapPlugin.getPluginInstance()
  plugin.isActive = false

proc pluginStartProcessing(clapPlugin: ptr clap.Plugin): bool {.cdecl.} =
  return true

proc pluginStopProcessing(clapPlugin: ptr clap.Plugin) {.cdecl.} =
  discard

proc pluginReset(clapPlugin: ptr clap.Plugin) {.cdecl.} =
  discard

proc pluginProcess(clapPlugin: ptr clap.Plugin, clapProcess: ptr clap.Process): clap.ProcessStatus {.cdecl.} =
  let plugin = clapPlugin.getPluginInstance()

  let frameCount = clapProcess.framesCount
  let eventCount = clapProcess.inEvents.size(clapProcess.inEvents)
  var eventIndex = 0'u32
  var nextEventIndex = if eventCount > 0: 0'u32 else: frameCount
  var frame = 0'u32

  plugin.parametersSyncMainThreadToAudioThread(clapProcess.outEvents)

  # let transportEvent = clapProcess.transport
  # if transportEvent != nil:
  #   let flags = cast[set[TransportFlags]](transportEvent.flags)
  #   if IsPlaying in flags:
  #     plugin.isPlaying = true
  #     plugin.setLatency(plugin.csCorrector.requiredLatency)
  #   else:
  #     plugin.isPlaying = false
      # plugin.csCorrector.reset()
      # plugin.setLatency(0)

  while frame < frameCount:
    while eventIndex < eventCount and nextEventIndex == frame:
      let eventHeader = clapProcess.inEvents.get(clapProcess.inEvents, eventIndex)
      if eventHeader.time != frame:
        nextEventIndex = eventHeader.time
        break

      if eventHeader.space_id == coreEventSpaceId:
        case eventHeader.`type`:
        of clap.EventType.ParamValue:
          let event = cast[ptr EventParamValue](eventHeader)
          plugin.handleEventParamValue(event)

        # of clap.EventType.Midi:
        #   let event = cast[ptr EventMidi](eventHeader)

        else:
          discard

      eventIndex += 1

      if eventIndex == eventCount:
        nextEventIndex = frameCount
        break

    frame = nextEventIndex

  return clap.ProcessStatus.Continue

proc pluginOnMainThread(clapPlugin: ptr clap.Plugin) {.cdecl.} =
  discard

proc pluginGetExtension(clapPlugin: ptr clap.Plugin, id: cstring): pointer {.cdecl.} =
  # if id == extGui: return addr(gui.extension)
  if id == extLatency: return addr(latencyExtension)
  if id == extNotePorts: return addr(noteportsExtension)
  if id == extParams: return addr(parametersExtension)
  if id == extTimerSupport: return addr(timerExtension)

proc pluginCreateInstance(id: int, host: ptr clap.Host): ptr clap.Plugin =
  let plugin = AudioPluginInstance()
  GcRef(plugin)
  plugin.clapHost = host
  plugin.clapPlugin = clap.Plugin(
    desc: addr(audioPlugins[id].clapDescriptor),
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


# ===================================================================================================
# Note Ports
# ===================================================================================================


var notePortsExtension = clap.PluginNotePorts(
  count: proc(clapPlugin: ptr clap.Plugin, isInput: bool): uint32 {.cdecl.} =
    return 1
  ,
  get: proc(clapPlugin: ptr clap.Plugin, index: uint32, isInput: bool, info: ptr clap.NotePortInfo): bool {.cdecl.} =
    info.id = 0
    info.supportedDialects = {NoteDialect.Midi}
    info.preferredDialect = {NoteDialect.Midi}
    "MIDI Port 1".writeTo(info.name, clap.nameSize)
    return true
)


# ===================================================================================================
# Latency
# ===================================================================================================


var latencyExtension = clap.PluginLatency(
  get: proc(clapPlugin: ptr clap.Plugin): uint32 {.cdecl.} =
    let plugin = clapPlugin.getPluginInstance()
    return uint32(plugin.latency)
)


# ===================================================================================================
# Parameters
# ===================================================================================================


proc parametersSyncMainThreadToAudioThread(plugin: AudioPluginInstance, outputEvents: ptr clap.OutputEvents) =
  plugin.parameterLock.acquire()
  for i in 0 ..< plugin.parameterCount:
    if plugin.mainThreadParameterChanged[i]:
      plugin.audioThreadParameterValue[i] = plugin.mainThreadParameterValue[i]
      plugin.mainThreadParameterChanged[i] = false
      var event = clap.EventParamValue()
      event.header.size = uint32(sizeof(event))
      event.header.time = 0
      event.header.spaceId = clap.coreEventSpaceId
      event.header.`type` = ParamValue
      event.header.flags = 0
      event.paramId = clap.Id(i)
      event.cookie = nil
      event.noteId = -1
      event.portIndex = -1
      event.channel = -1
      event.key = -1
      event.value = plugin.audioThreadParameterValue[i]
      discard outputEvents.tryPush(outputEvents, addr(event.header))
  plugin.parameterLock.release()

# proc parametersSyncAudioThreadToMainThread(plugin: AudioPluginInstance) =
#   plugin.parameterLock.acquire()
#   for i in 0 ..< plugin.parameterCount:
#     if plugin.audioThreadParameterChanged[i]:
#       plugin.mainThreadParameterValue[i] = plugin.audioThreadParameterValue[i]
#       plugin.audioThreadParameterChanged[i] = false
#   plugin.parameterLock.release()

proc handleEventParamValue(plugin: AudioPluginInstance, event: ptr clap.EventParamValue) =
  let id = event.paramId
  plugin.parameterLock.acquire()
  plugin.audioThreadParameterValue[id] = event.value
  plugin.audioThreadParameterChanged[id] = true
  plugin.parameterLock.release()

var parametersExtension = clap.PluginParams(
  count: proc(clapPlugin: ptr clap.Plugin): uint32 {.cdecl.} =
    let plugin = clapPlugin.getPluginInstance()
    return uint32(plugin.parameterCount)
  ,

  getInfo: proc(clapPlugin: ptr clap.Plugin, paramIndex: uint32, paramInfo: ptr clap.ParamInfo): bool {.cdecl.} =
    let plugin = clapPlugin.getPluginInstance()
    if plugin.parameterCount == 0:
      return false
    paramInfo.id = uint32(plugin.parameterInfo[paramIndex].id)
    paramInfo.flags = cast[uint32](plugin.parameterInfo[paramIndex].flags)
    plugin.parameterInfo[paramIndex].name.writeTo(paramInfo.name, clap.nameSize)
    plugin.parameterInfo[paramIndex].module.writeTo(paramInfo.module, clap.pathSize)
    paramInfo.minValue = plugin.parameterInfo[paramIndex].minValue
    paramInfo.maxValue = plugin.parameterInfo[paramIndex].maxValue
    paramInfo.defaultValue = plugin.parameterInfo[paramIndex].defaultValue
    return true
  ,

  getValue: proc(clapPlugin: ptr clap.Plugin, paramId: clap.Id, outValue: ptr float): bool {.cdecl.} =
    let plugin = clapPlugin.getPluginInstance()
    if plugin.parameterCount == 0:
      return false
    plugin.parameterLock.acquire()
    if plugin.mainThreadParameterChanged[paramId]:
      outValue[] = plugin.mainThreadParameterValue[paramId]
    else:
      outValue[] = plugin.audioThreadParameterValue[paramId]
    plugin.parameterLock.release()
    return true
  ,

  valueToText: proc(clapPlugin: ptr clap.Plugin, paramId: clap.Id, value: float64, outBuffer: ptr UncheckedArray[char], outBufferCapacity: uint32): bool {.cdecl.} =
    let plugin = clapPlugin.getPluginInstance()
    if plugin.parameterCount == 0:
      return false
    var valueStr = value.formatFloat(ffDecimal, 3)
    valueStr.writeTo(outBuffer, outBufferCapacity)
    return true
  ,

  textToValue: proc(clapPlugin: ptr clap.Plugin, paramId: clap.Id, paramValueText: cstring, outValue: ptr float64): bool {.cdecl.} =
    let plugin = clapPlugin.getPluginInstance()
    if plugin.parameterCount == 0:
      return false
    var value: float
    let res = parseutils.parseFloat($paramValueText, value)
    if res != 0:
      outValue[] = value
      return true
    else:
      return false
  ,

  flush: proc(clapPlugin: ptr clap.Plugin, input: ptr clap.InputEvents, output: ptr clap.OutputEvents) {.cdecl.} =
    let plugin = clapPlugin.getPluginInstance()
    let eventCount = input.size(input)
    plugin.parametersSyncMainThreadToAudioThread(output)
    for i in 0 ..< eventCount:
      let eventHeader = input.get(input, i)
      if eventHeader.`type` == ParamValue:
        let event = cast[ptr clap.EventParamValue](eventHeader)
        plugin.handleEventParamValue(event)
  ,
)


# ===================================================================================================
# Timer
# ===================================================================================================


var timerExtension = clap.PluginTimerSupport(
  onTimer: proc(clapPlugin: ptr clap.Plugin, timerId: clap.Id) {.cdecl.} =
    let plugin = clapPlugin.getPluginInstance()
    if plugin.timerIdToProcTable.hasKey(timerId):
      plugin.timerIdToProcTable[timerId](plugin)
)


# ===================================================================================================
# Factory
# ===================================================================================================


var clapFactory = clap.PluginFactory(
  getPluginCount: proc(factory: ptr clap.PluginFactory): uint32 {.cdecl.} =
    return uint32(audioPlugins.len)
  ,
  getPluginDescriptor: proc(factory: ptr clap.PluginFactory, index: uint32): ptr clap.PluginDescriptor {.cdecl.} =
    return addr(audioPlugins[index].clapDescriptor)
  ,
  createPlugin: proc(factory: ptr clap.PluginFactory, host: ptr clap.Host, pluginId: cstring): ptr clap.Plugin {.cdecl.} =
    if not clap.versionIsCompatible(host.clapVersion):
      return nil

    for i in 0 ..< audioPlugins.len:
      let descriptor = audioPlugins[i].clapDescriptor
      if pluginId == descriptor.id:
        return pluginCreateInstance(i, host)
)


# ===================================================================================================
# Entry
# ===================================================================================================


proc NimMain() {.importc.}

proc mainInit(plugin_path: cstring): bool {.cdecl.} =
  NimMain()
  return true

proc mainDeinit() {.cdecl.} =
  discard

proc mainGetFactory(factoryId: cstring): pointer {.cdecl.} =
  if factoryId == clap.pluginFactoryId:
    return clapFactory.addr

type MainPluginEntry = clap.PluginEntry

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

CLAP_EXPORT const `MainPluginEntry` clap_entry = {
  .clapVersion = {1, 1, 7},
  .init = `mainInit`,
  .deinit = `mainDeinit`,
  .getFactory = `mainGetFactory`,
};
""".}