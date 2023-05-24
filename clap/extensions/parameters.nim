import std/parseutils
import std/strutils
import ../binding
import ../common

proc toClapParamInfoFlags(flags: set[ParameterFlag]): clap_param_info_flags =
  if IsStepped in flags: result = result or CLAP_PARAM_IS_STEPPED
  if IsPeriodic in flags: result = result or CLAP_PARAM_IS_PERIODIC
  if IsHidden in flags: result = result or CLAP_PARAM_IS_HIDDEN
  if IsReadOnly in flags: result = result or CLAP_PARAM_IS_READ_ONLY
  if IsBypass in flags: result = result or CLAP_PARAM_IS_BYPASS
  if IsAutomatable in flags: result = result or CLAP_PARAM_IS_AUTOMATABLE
  if IsAutomatablePerNote_Id in flags: result = result or CLAP_PARAM_IS_AUTOMATABLE_PER_NOTE_ID
  if IsAutomatablePerKey in flags: result = result or CLAP_PARAM_IS_AUTOMATABLE_PER_KEY
  if IsAutomatablePerChannel in flags: result = result or CLAP_PARAM_IS_AUTOMATABLE_PER_CHANNEL
  if IsAutomatablePerPort in flags: result = result or CLAP_PARAM_IS_AUTOMATABLE_PER_PORT
  if IsModulatable in flags: result = result or CLAP_PARAM_IS_MODULATABLE
  if IsModulatablePerNoteId in flags: result = result or CLAP_PARAM_IS_MODULATABLE_PER_NOTE_ID
  if IsModulatablePerKey in flags: result = result or CLAP_PARAM_IS_MODULATABLE_PER_KEY
  if IsModulatablePerChannel in flags: result = result or CLAP_PARAM_IS_MODULATABLE_PER_CHANNEL
  if IsModulatablePerPort in flags: result = result or CLAP_PARAM_IS_MODULATABLE_PER_PORT
  if Requires_Process in flags: result = result or CLAP_PARAM_REQUIRES_PROCESS
  return result

proc count*[T](plugin: ptr clap_plugin_t): uint32 {.cdecl.} =
  let plugin = cast[T](plugin.plugin_data)
  return uint32(plugin.parameterCount)

proc getInfo*[T](plugin: ptr clap_plugin_t, param_index: uint32, param_info: ptr clap_param_info_t): bool {.cdecl.} =
  let plugin = cast[T](plugin.plugin_data)
  if plugin.parameterCount == 0:
    return false
  let info = plugin.parameterInfo
  param_info.id = uint32(info[param_index].id)
  param_info.flags = info[param_index].flags.toClapParamInfoFlags()
  writeStringToBuffer(info[param_index].name, param_info.name, CLAP_NAME_SIZE)
  writeStringToBuffer(info[param_index].module, param_info.module, CLAP_PATH_SIZE)
  param_info.minValue = info[param_index].minValue
  param_info.maxValue = info[param_index].maxValue
  param_info.defaultValue = info[param_index].defaultValue
  return true

proc getValue*[T](plugin: ptr clap_plugin_t, param_id: clap_id, out_value: ptr float): bool {.cdecl.} =
  let plugin = cast[T](plugin.plugin_data)
  if plugin.parameterCount == 0:
    return false
  out_value[] = plugin.parameter(param_id)
  return true

proc valueToText*[T](plugin: ptr clap_plugin_t, param_id: clap_id, value: float, out_buffer: ptr UncheckedArray[char], out_buffer_capacity: uint32): bool {.cdecl.} =
  let plugin = cast[T](plugin.plugin_data)
  if plugin.parameterCount == 0:
    return false
  var valueStr = value.formatFloat(ffDecimal, 3)
  writeStringToBuffer(valueStr, out_buffer, out_buffer_capacity)
  return true

proc textToValue*[T](plugin: ptr clap_plugin_t, param_id: clap_id, param_value_text: cstring, out_value: ptr float): bool {.cdecl.} =
  let plugin = cast[T](plugin.plugin_data)
  if plugin.parameterCount == 0:
    return false
  var value: float
  let res = parseutils.parseFloat($param_value_text, value)
  if res != 0:
    out_value[] = value
    return true
  else:
    return false

proc flush*[T](plugin: ptr clap_plugin_t, input: ptr clap_input_events_t, output: ptr clap_output_events_t) {.cdecl.} =
  let plugin = cast[T](plugin.plugin_data)
  let eventCount = input.size(input)
  for i in 0 ..< eventCount:
    let eventHeader = input.get(input, i)
    plugin.dispatchParameterEvent(eventHeader)