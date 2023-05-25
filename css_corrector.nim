import clap/public

type
  CssCorrectorParameter = enum
    LegatoFirstNoteDelay
    LegatoPortamentoDelay
    LegatoSlowDelay
    LegatoMediumDelay
    LegatoFastDelay

  CssCorrector = ref object of AudioPlugin[CssCorrectorParameter]
    foo: int

proc init(plugin: CssCorrector) =
  discard

proc destroy(plugin: CssCorrector) =
  discard

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

# proc onProcess(plugin: CssCorrector, frameCount: int) =
#   discard

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