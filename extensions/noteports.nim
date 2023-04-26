{.experimental: "overloadableEnums".}

import ../clap

var extension* = clap.PluginNotePorts(
  count: proc(clapPlugin: ptr clap.Plugin, isInput: bool): uint32 {.cdecl.} =
    return 1
  ,
  get: proc(clapPlugin: ptr clap.Plugin, index: uint32, isInput: bool, info: ptr clap.NotePortInfo): bool {.cdecl.} =
    info.id = 0
    info.supportedDialects = {NoteDialect.Midi}
    info.preferredDialect = {NoteDialect.Midi}
    # clap.write_string(info.name[:], "MIDI Port 1")
    return true
)