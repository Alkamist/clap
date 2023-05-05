import std/parseutils
import std/strutils
import ../binding
import ../shared

proc parameterCount*(instance: AudioPlugin): int =
  return instance.info.parameterInfo.len

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

var parametersExtension* = clap_plugin_params_t(
  count: proc(plugin: ptr clap_plugin_t): uint32 {.cdecl.} =
    let instance = plugin.getInstance()
    return uint32(instance.parameterCount)
  ,

  get_info: proc(plugin: ptr clap_plugin_t, param_index: uint32, param_info: ptr clap_param_info_t): bool {.cdecl.} =
    let instance = plugin.getInstance()
    if instance.parameterCount == 0:
      return false
    let info = instance.info.parameterInfo
    param_info.id = uint32(info[param_index].id)
    param_info.flags = cast[uint32](info[param_index].flags)
    writeStringToBuffer(info[param_index].name, param_info.name, CLAP_NAME_SIZE)
    writeStringToBuffer(info[param_index].module, param_info.module, CLAP_PATH_SIZE)
    param_info.minValue = info[param_index].minValue
    param_info.maxValue = info[param_index].maxValue
    param_info.defaultValue = info[param_index].defaultValue
    return true
  ,

  get_value: proc(plugin: ptr clap_plugin_t, param_id: clap_id, out_value: ptr float): bool {.cdecl.} =
    let instance = plugin.getInstance()
    if instance.parameterCount == 0:
      return false
    instance.parameterLock.acquire()
    if instance.mainThreadParameterChanged[param_id]:
      out_value[] = instance.mainThreadParameterValue[param_id]
    else:
      out_value[] = instance.audioThreadParameterValue[param_id]
    instance.parameterLock.release()
    return true
  ,

  valueToText: proc(plugin: ptr clap_plugin_t, param_id: clap_id, value: cdouble, out_buffer: ptr UncheckedArray[char], out_buffer_capacity: uint32): bool {.cdecl.} =
    let instance = plugin.getInstance()
    if instance.parameterCount == 0:
      return false
    var valueStr = value.formatFloat(ffDecimal, 3)
    writeStringToBuffer(valueStr, out_buffer, out_buffer_capacity)
    return true
  ,

  textToValue: proc(plugin: ptr clap_plugin_t, param_id: clap_id, param_value_text: cstring, out_value: ptr cdouble): bool {.cdecl.} =
    let instance = plugin.getInstance()
    if instance.parameterCount == 0:
      return false
    var value: float
    let res = parseutils.parseFloat($param_value_text, value)
    if res != 0:
      out_value[] = value
      return true
    else:
      return false
  ,

  flush: proc(plugin: ptr clap_plugin_t, input: ptr clap_input_events_t, output: ptr clap_output_events_t) {.cdecl.} =
    let instance = plugin.getInstance()
    let eventCount = input.size(input)
    instance.syncParametersMainThreadToAudioThread(output)
    for i in 0 ..< eventCount:
      let eventHeader = input.get(input, i)
      if eventHeader.`type` == CLAP_EVENT_PARAM_VALUE:
        let event = cast[ptr clap_event_param_value_t](eventHeader)
        instance.handleParameterValueEvent(event)
  ,
)