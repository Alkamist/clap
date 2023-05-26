{.experimental: "codeReordering".}

import std/json
import std/locks
import reaper
import audioplugin as ap
import logic

type
  CssCorrectorParameter = enum
    LegatoFirstNoteDelay
    LegatoPortamentoDelay
    LegatoSlowDelay
    LegatoMediumDelay
    LegatoFastDelay

  CssCorrectorPresetV1* = object
    presetVersion*: int
    legatoFirstNoteDelay*: float
    legatoPortamentoDelay*: float
    legatoSlowDelay*: float
    legatoMediumDelay*: float
    legatoFastDelay*: float

  CssCorrector = ref object of AudioPlugin[CssCorrectorParameter]
    logic: CsCorrectorLogic
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

  plugin.logic = CsCorrectorLogic.new()
  plugin.logic.legatoDelayVelocities[0] = 20
  plugin.logic.legatoDelayVelocities[1] = 64
  plugin.logic.legatoDelayVelocities[2] = 100
  plugin.logic.legatoDelayVelocities[3] = 128
  plugin.updateLogicParameters()

proc destroy(plugin: CssCorrector) =
  plugin.unregisterTimer("DebugTimer")
  plugin.debugStringMutex.deinitLock()

proc activate(plugin: CssCorrector) =
  plugin.updateLogicParameters()

proc deactivate(plugin: CssCorrector) =
  discard

proc reset(plugin: CssCorrector) =
  plugin.logic.reset()

proc onParameterEvent(plugin: CssCorrector, event: ParameterEvent) =
  plugin.updateLogicParameters()

proc onTransportEvent(plugin: CssCorrector, event: TransportEvent) =
  plugin.logic.processTransportEvent(event)

proc onMidiEvent(plugin: CssCorrector, event: MidiEvent) =
  plugin.logic.processMidiEvent(plugin, event)

proc onProcess(plugin: CssCorrector, frameCount: int) =
  plugin.logic.sendNoteEvents(plugin, frameCount)

proc savePreset(plugin: CssCorrector): string =
  let preset = CssCorrectorPresetV1(
    presetVersion: 1,
    legatoFirstNoteDelay: plugin.parameter(LegatoFirstNoteDelay),
    legatoPortamentoDelay: plugin.parameter(LegatoPortamentoDelay),
    legatoSlowDelay: plugin.parameter(LegatoSlowDelay),
    legatoMediumDelay: plugin.parameter(LegatoMediumDelay),
    legatoFastDelay: plugin.parameter(LegatoFastDelay),
  )
  let presetJson = %*preset
  return $presetJson

proc loadPreset(plugin: CssCorrector, data: string) =
  let presetJson = parseJson(data)

  template loadParameter(id, key): untyped =
    plugin.setParameter(id, presetJson{key}.getFloat(plugin.parameterDefaultValue(id)))

  loadParameter(LegatoFirstNoteDelay, "legatoFirstNoteDelay")
  loadParameter(LegatoPortamentoDelay, "legatoPortamentoDelay")
  loadParameter(LegatoSlowDelay, "legatoSlowDelay")
  loadParameter(LegatoMediumDelay, "legatoMediumDelay")
  loadParameter(LegatoFastDelay, "legatoFastDelay")

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

proc updateLogicParameters(plugin: CssCorrector) =
  plugin.logic.legatoFirstNoteDelay = plugin.millisecondsToSamples(plugin.parameter(LegatoFirstNoteDelay))
  plugin.logic.legatoDelayTimes[0] = plugin.millisecondsToSamples(plugin.parameter(LegatoPortamentoDelay))
  plugin.logic.legatoDelayTimes[1] = plugin.millisecondsToSamples(plugin.parameter(LegatoSlowDelay))
  plugin.logic.legatoDelayTimes[2] = plugin.millisecondsToSamples(plugin.parameter(LegatoMediumDelay))
  plugin.logic.legatoDelayTimes[3] = plugin.millisecondsToSamples(plugin.parameter(LegatoFastDelay))
  plugin.setLatency(plugin.logic.requiredLatency)