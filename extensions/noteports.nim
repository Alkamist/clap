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
    "MIDI Port 1".writeTo(info.name, clap.nameSize)
    return true
)