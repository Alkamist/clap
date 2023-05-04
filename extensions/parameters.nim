import std/strutils
import std/parseutils
import ../clap
import ../userplugin

proc syncMainThreadToAudioThread*(plugin: UserPlugin, outputEvents: ptr clap.OutputEvents) =
  plugin.parameterLock.acquire()

  for id in ParameterId:
    if plugin.mainThreadParameterChanged[id]:
      plugin.audioThreadParameterValue[id] = plugin.mainThreadParameterValue[id]
      plugin.mainThreadParameterChanged[id] = false

      var event = clap.EventParamValue()
      event.header.size = uint32(sizeof(event))
      event.header.time = 0
      event.header.spaceId = clap.coreEventSpaceId
      event.header.`type` = ParamValue
      event.header.flags = 0
      event.paramId = clap.Id(id)
      event.cookie = nil
      event.noteId = -1
      event.portIndex = -1
      event.channel = -1
      event.key = -1
      event.value = plugin.audioThreadParameterValue[id]
      discard outputEvents.tryPush(outputEvents, addr(event.header))

  plugin.parameterLock.release()

proc syncAudioThreadToMainThread*(plugin: UserPlugin) =
  plugin.parameterLock.acquire()

  for id in ParameterId:
    if plugin.audioThreadParameterChanged[id]:
      plugin.mainThreadParameterValue[id] = plugin.audioThreadParameterValue[id]
      plugin.audioThreadParameterChanged[id] = false

  plugin.parameterLock.release()

var extension* = clap.PluginParams(
  count: proc(clapPlugin: ptr clap.Plugin): uint32 {.cdecl.} =
    return uint32(parameterInfo.len)
  ,

  getInfo: proc(clapPlugin: ptr clap.Plugin, paramIndex: uint32, paramInfo: ptr clap.ParamInfo): bool {.cdecl.} =
    let id = ParameterId(paramIndex)
    paramInfo.id = uint32(parameterInfo[id].id)
    paramInfo.flags = cast[uint32](parameterInfo[id].flags)
    parameterInfo[id].name.writeTo(paramInfo.name, clap.nameSize)
    parameterInfo[id].module.writeTo(paramInfo.module, clap.pathSize)
    paramInfo.minValue = parameterInfo[id].minValue
    paramInfo.maxValue = parameterInfo[id].maxValue
    paramInfo.defaultValue = parameterInfo[id].defaultValue
    return true
  ,

  getValue: proc(clapPlugin: ptr clap.Plugin, paramId: clap.Id, outValue: ptr float): bool {.cdecl.} =
    let plugin = clapPlugin.getUserPlugin()
    let id = ParameterId(paramId)
    plugin.parameterLock.acquire()
    if plugin.mainThreadParameterChanged[id]:
      outValue[] = plugin.mainThreadParameterValue[id]
    else:
      outValue[] = plugin.audioThreadParameterValue[id]
    plugin.parameterLock.release()
    return true
  ,

  valueToText: proc(clapPlugin: ptr clap.Plugin, paramId: clap.Id, value: float64, outBuffer: ptr UncheckedArray[char], outBufferCapacity: uint32): bool {.cdecl.} =
    if parameterInfo.len == 0:
      return false
    var valueStr = value.formatFloat(ffDecimal, 3)
    valueStr.writeTo(outBuffer, outBufferCapacity)
    return true
  ,

  textToValue: proc(clapPlugin: ptr clap.Plugin, paramId: clap.Id, paramValueText: cstring, outValue: ptr float64): bool {.cdecl.} =
    if parameterInfo.len == 0:
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
    let plugin = clapPlugin.getUserPlugin()
    let eventCount = input.size(input)
    syncMainThreadToAudioThread(plugin, output)
    for i in 0 ..< eventCount:
      let eventHeader = input.get(input, i)
      if eventHeader.`type` == ParamValue:
        let event = cast[ptr clap.EventParamValue](eventHeader)
        plugin.handleEventParamValue(event)
  ,
)