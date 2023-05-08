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

let dispatcher = registerAudioPlugin(CsCorrector,
  id = "com.alkamist.CsCorrector",
  name = "Cs Corrector",
  vendor = "Alkamist Audio",
  url = "",
  manualUrl = "",
  supportUrl = "",
  version = "0.1.0",
  description = "",
)

dispatcher.addParameter(LegatoFirstNoteDelay, "Legato First Note Delay", -1000.0, 1000.0, -60.0, {IsAutomatable})
dispatcher.addParameter(LegatoPortamentoDelay, "Legato Portamento Delay", -1000.0, 1000.0, -300.0, {IsAutomatable})
dispatcher.addParameter(LegatoSlowDelay, "Legato Slow Delay", -1000.0, 1000.0, -300.0, {IsAutomatable})
dispatcher.addParameter(LegatoMediumDelay, "Legato Medium Delay", -1000.0, 1000.0, -300.0, {IsAutomatable})
dispatcher.addParameter(LegatoFastDelay, "Legato Fast Delay", -1000.0, 1000.0, -150.0, {IsAutomatable})

dispatcher.onMidiEvent = proc(plugin: AudioPlugin, event: MidiEvent) =
  # var event = event
  # event.time += 48000
  plugin.sendMidiEvent(event)