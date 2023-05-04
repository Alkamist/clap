{.experimental: "codeReordering".}

import audioplugin

type
  CsCorrectorParameter* = enum
    LegatoFirstNoteDelay
    LegatoPortamentoDelay
    LegatoSlowDelay
    LegatoMediumDelay
    LegatoFastDelay

var csCorrector = AudioPlugin.new(
  id = "com.alkamist.csCorrector",
  name = "Cs Corrector",
  vendor = "Alkamist Audio",
  url = "",
  manualUrl = "",
  supportUrl = "",
  version = "0.1.0",
  description = "",
)

csCorrector.addParameter(LegatoFirstNoteDelay, "Legato First Note Delay", -1000.0, 1000.0, -60.0, {IsAutomatable})
csCorrector.addParameter(LegatoPortamentoDelay, "Legato Portamento Delay", -1000.0, 1000.0, -300.0, {IsAutomatable})
csCorrector.addParameter(LegatoSlowDelay, "Legato Slow Delay", -1000.0, 1000.0, -300.0, {IsAutomatable})
csCorrector.addParameter(LegatoMediumDelay, "Legato Medium Delay", -1000.0, 1000.0, -300.0, {IsAutomatable})
csCorrector.addParameter(LegatoFastDelay, "Legato Fast Delay", -1000.0, 1000.0, -150.0, {IsAutomatable})

csCorrector.onMidiEvent = proc(plugin: AudioPlugin, event: MidiEvent) =
  var outEvent = event
  outEvent.time += 48000
  plugin.sendMidiEvent(outEvent)