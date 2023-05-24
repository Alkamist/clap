import ../binding
import ../common

proc count*[T](plugin: ptr clap_plugin_t, is_input: bool): uint32 {.cdecl.} =
  return 1

proc get*[T](plugin: ptr clap_plugin_t, index: uint32, is_input: bool, info: ptr clap_note_port_info_t): bool {.cdecl.} =
  info.id = 0
  info.supported_dialects = CLAP_NOTE_DIALECT_MIDI
  info.preferred_dialect = CLAP_NOTE_DIALECT_MIDI
  writeStringToBuffer("MIDI Port 1", info.name, CLAP_NAME_SIZE)
  return true