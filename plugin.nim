{.experimental: "codeReordering".}

import ./audioplugin

type
  CsCorrectorParameter* = enum
    LegatoFirstNoteDelay
    LegatoPortamentoDelay
    LegatoSlowDelay
    LegatoMediumDelay
    LegatoFastDelay

  CsCorrector* = ref object of AudioPlugin
    stuff*: int

let csCorrectorInfo = registerAudioPlugin(CsCorrector,
  id = "com.alkamist.csCorrector",
  name = "Cs Corrector",
  vendor = "Alkamist Audio",
  url = "",
  manualUrl = "",
  supportUrl = "",
  version = "0.1.0",
  description = "",
)

csCorrectorInfo.addParameter(LegatoFirstNoteDelay, "Legato First Note Delay", -1000.0, 1000.0, -60.0, {IsAutomatable})
csCorrectorInfo.addParameter(LegatoPortamentoDelay, "Legato Portamento Delay", -1000.0, 1000.0, -300.0, {IsAutomatable})
csCorrectorInfo.addParameter(LegatoSlowDelay, "Legato Slow Delay", -1000.0, 1000.0, -300.0, {IsAutomatable})
csCorrectorInfo.addParameter(LegatoMediumDelay, "Legato Medium Delay", -1000.0, 1000.0, -300.0, {IsAutomatable})
csCorrectorInfo.addParameter(LegatoFastDelay, "Legato Fast Delay", -1000.0, 1000.0, -150.0, {IsAutomatable})

csCorrectorInfo.onMidiEvent = proc(plugin: AudioPlugin, event: MidiEvent) =
  plugin.sendMidiEvent(event)