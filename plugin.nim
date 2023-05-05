{.experimental: "codeReordering".}

import ./audioplugin
import ./cscorrectorlogic

type
  CsCorrectorParameter* = enum
    LegatoFirstNoteDelay
    LegatoPortamentoDelay
    LegatoSlowDelay
    LegatoMediumDelay
    LegatoFastDelay

var csCorrectorPlugin = AudioPlugin.new(
  id = "com.alkamist.csCorrector",
  name = "Cs Corrector",
  vendor = "Alkamist Audio",
  url = "",
  manualUrl = "",
  supportUrl = "",
  version = "0.1.0",
  description = "",
)

csCorrectorPlugin.addParameter(LegatoFirstNoteDelay, "Legato First Note Delay", -1000.0, 1000.0, -60.0, {IsAutomatable})
csCorrectorPlugin.addParameter(LegatoPortamentoDelay, "Legato Portamento Delay", -1000.0, 1000.0, -300.0, {IsAutomatable})
csCorrectorPlugin.addParameter(LegatoSlowDelay, "Legato Slow Delay", -1000.0, 1000.0, -300.0, {IsAutomatable})
csCorrectorPlugin.addParameter(LegatoMediumDelay, "Legato Medium Delay", -1000.0, 1000.0, -300.0, {IsAutomatable})
csCorrectorPlugin.addParameter(LegatoFastDelay, "Legato Fast Delay", -1000.0, 1000.0, -150.0, {IsAutomatable})

proc getUserData(plugin: AudioPluginInstance): CsCorrectorLogic =
  return cast[CsCorrectorLogic](plugin.userData)

csCorrectorPlugin.onInit = proc(plugin: AudioPluginInstance) =
  let cs = CsCorrectorLogic()
  GcRef(cs)
  plugin.userData = cast[pointer](cs)

csCorrectorPlugin.onDestroy = proc(plugin: AudioPluginInstance) =
  let cs = plugin.getUserData()
  GcUnRef(cs)

csCorrectorPlugin.onMidiEvent = proc(plugin: AudioPluginInstance, event: MidiEvent) =
  let cs = plugin.getUserData()
  cs.processEvent(cscorrectorlogic.Event(
    time: event.time,
    data: event.data,
  ))

csCorrectorPlugin.onBlock = proc(plugin: AudioPluginInstance, blockSize: int) =
  let cs = plugin.getUserData()
  let csEvents = cs.extractEvents(blockSize)
  for i in 0 ..< csEvents.len:
    let csEvent = csEvents[i]
    let midiEvent = MidiEvent(
      time: csEvent.time,
      port: 0,
      data: csEvent.data,
    )
    plugin.sendMidiEvent(midiEvent)

# proc millisToSamples*(plugin: UserPlugin, millis: float): int =
#   return int(millis * plugin.sampleRate * 0.001)