import clap/public

type
  Plugin = ref object of AudioPlugin
    foo: int

proc init(plugin: Plugin) =
  discard

proc destroy(plugin: Plugin) =
  discard

proc activate(plugin: Plugin) =
  discard

proc deactivate(plugin: Plugin) =
  discard

proc reset(plugin: Plugin) =
  discard

proc onParameterEvent(plugin: Plugin, event: ParameterEvent) =
  discard

proc onTransportEvent(plugin: Plugin, event: TransportEvent) =
  discard

proc onMidiEvent(plugin: Plugin, event: MidiEvent) =
  discard

proc onProcess(plugin: Plugin, frameCount: int) =
  discard

proc savePreset(plugin: Plugin): string =
  return ""

proc loadPreset(plugin: Plugin, data: openArray[byte]) =
  discard

exportClapPlugin[Plugin](
  id = "com.alkamist.DemoPlugin",
  name = "Demo Plugin",
  vendor = "Alkamist Audio",
  url = "",
  manualUrl = "",
  supportUrl = "",
  version = "0.1.0",
  description = "",
)