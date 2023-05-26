{.experimental: "codeReordering".}

import std/locks
import reaper
import notequeue as nq
import audioplugin as ap

type
  CssCorrectorParameter = enum
    LegatoFirstNoteDelay
    LegatoPortamentoDelay
    LegatoSlowDelay
    LegatoMediumDelay
    LegatoFastDelay

  CssCorrector = ref object of AudioPlugin[CssCorrectorParameter]
    debugStringMutex: Lock
    debugString: string
    debugStringChanged: bool

proc init(plugin: CssCorrector) =
  plugin.debugStringMutex.initLock()

  let reaperPluginInfo = cast[ptr reaper_plugin_info_t](plugin.clapHost.get_extension(plugin.clapHost, "cockos.reaper_extension"))
  reaper.loadFunctions(reaperPluginInfo)

  plugin.registerTimer("DebugTimer", 0, proc(plugin: pointer) =
    let plugin = cast[CssCorrector](plugin)
    if plugin.debugStringChanged:
      plugin.debugStringMutex.acquire()
      reaper.ShowConsoleMsg(cstring(plugin.debugString))
      plugin.debugString = ""
      plugin.debugStringChanged = false
      plugin.debugStringMutex.release()
  )

  plugin.noteQueue = NoteQueue.new(1024)

proc destroy(plugin: CssCorrector) =
  plugin.unregisterTimer("DebugTimer")
  plugin.debugStringMutex.deinitLock()

proc activate(plugin: CssCorrector) =
  discard

proc deactivate(plugin: CssCorrector) =
  discard

proc reset(plugin: CssCorrector) =
  discard

proc onParameterEvent(plugin: CssCorrector, event: ParameterEvent) =
  discard

proc onTransportEvent(plugin: CssCorrector, event: TransportEvent) =
  discard

proc onMidiEvent(plugin: CssCorrector, event: MidiEvent) =
  discard

proc onProcess(plugin: CssCorrector, frameCount: int) =
  discard

proc savePreset(plugin: CssCorrector): string =
  return ""

proc loadPreset(plugin: CssCorrector, data: openArray[byte]) =
  discard

proc makeParam(id: CssCorrectorParameter, name: string, defaultValue: float): ParameterInfo =
  result.id = int(id)
  result.name = name
  result.minValue = -500.0
  result.maxValue = 500.0
  result.defaultValue = defaultValue
  result.flags = {IsAutomatable}
  result.module = ""

let parameterInfo = [
  makeParam(LegatoFirstNoteDelay, "Legato First Note Delay", -60.0),
  makeParam(LegatoPortamentoDelay, "Legato Portamento Delay", -300.0),
  makeParam(LegatoSlowDelay, "Legato Slow Delay", -300.0),
  makeParam(LegatoMediumDelay, "Legato Medium Delay", -300.0),
  makeParam(LegatoFastDelay, "Legato Fast Delay", -150.0),
]

exportClapPlugin[CssCorrector](
  id = "com.alkamist.CssCorrector",
  name = "Css Corrector",
  vendor = "Alkamist Audio",
  url = "",
  manualUrl = "",
  supportUrl = "",
  version = "0.1.0",
  description = "",
  parameterInfo = parameterInfo,
)

proc debug(plugin: CssCorrector, args: varargs[string, `$`]) =
  var output = ""
  for arg in args:
    output &= arg & "\n"
  plugin.debugStringMutex.acquire()
  plugin.debugString = output
  plugin.debugStringChanged = true
  plugin.debugStringMutex.release()