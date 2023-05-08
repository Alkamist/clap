import std/parseutils
import std/strutils
import ../binding
import ../shared

var parametersExtension* = clap_plugin_params_t(
  count: proc(plugin: ptr clap_plugin_t): uint32 {.cdecl.} =
    let instance = plugin.getInstance()
    return uint32(instance.parameterCount)
  ,
  get_info: proc(plugin: ptr clap_plugin_t, param_index: uint32, param_info: ptr clap_param_info_t): bool {.cdecl.} =
    let instance = plugin.getInstance()
    if instance.parameterCount == 0:
      return false
    let info = instance.dispatcher.parameterInfo
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
  value_to_text: proc(plugin: ptr clap_plugin_t, param_id: clap_id, value: cdouble, out_buffer: ptr UncheckedArray[char], out_buffer_capacity: uint32): bool {.cdecl.} =
    let instance = plugin.getInstance()
    if instance.parameterCount == 0:
      return false
    var valueStr = value.formatFloat(ffDecimal, 3)
    writeStringToBuffer(valueStr, out_buffer, out_buffer_capacity)
    return true
  ,
  text_to_value: proc(plugin: ptr clap_plugin_t, param_id: clap_id, param_value_text: cstring, out_value: ptr cdouble): bool {.cdecl.} =
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