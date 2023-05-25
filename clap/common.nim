import std/typetraits
import ./binding
import ./types; export types

template writeStringToBuffer*(str: string, buffer, length: untyped) =
  bind elementType
  let strLen = str.len
  for i in 0 ..< int(length):
    if i < strLen:
      buffer[i] = elementType(buffer)(str[i])
    else:
      buffer[i] = elementType(buffer)(0)
      break

proc dispatchParameterEvent*[T](plugin: T, eventHeader: ptr clap_event_header_t) =
  mixin onParameterEvent
  case eventHeader.`type`:
  of CLAP_EVENT_PARAM_VALUE:
    var clapEvent = cast[ptr clap_event_param_value_t](eventHeader)
    plugin.setParameter(clapEvent.param_id, clapEvent.value)
    plugin.onParameterEvent(ParameterEvent(
      id: int(clapEvent.param_id),
      kind: Value,
      note_id: int(clapEvent.note_id),
      port: int(clapEvent.port_index),
      channel: int(clapEvent.channel),
      key: int(clapEvent.key),
      value: clapEvent.value,
    ))
  else:
    discard