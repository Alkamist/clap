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

  CsCorrectorPresetV1* = object
    size*: uint64
    version*: uint64
    parameters*: array[CsCorrectorParameter, float64]

  CsCorrector* = ref object of AudioPlugin
    logic*: CsCorrectorLogic
    isPlaying*: bool
    wasPlaying*: bool

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

dispatcher.onCreateInstance = proc(plugin: AudioPlugin) =
  let plugin = CsCorrector(plugin)
  plugin.logic = CsCorrectorLogic()

dispatcher.onDestroyInstance = proc(plugin: AudioPlugin) =
  discard

dispatcher.onParameterEvent = proc(plugin: AudioPlugin, event: ParameterEvent) =
  let plugin = CsCorrector(plugin)
  case event.kind:
  of Value:
    let parameter = CsCorrectorParameter(event.index)
    case parameter:
    of LegatoFirstNoteDelay: plugin.logic.legatoFirstNoteDelay = plugin.secondsToSamples(event.value * 0.001)
    of LegatoPortamentoDelay: plugin.logic.legatoPortamentoDelay = plugin.secondsToSamples(event.value * 0.001)
    of LegatoSlowDelay: plugin.logic.legatoSlowDelay = plugin.secondsToSamples(event.value * 0.001)
    of LegatoMediumDelay: plugin.logic.legatoMediumDelay = plugin.secondsToSamples(event.value * 0.001)
    of LegatoFastDelay: plugin.logic.legatoFastDelay = plugin.secondsToSamples(event.value * 0.001)
    plugin.setLatency(plugin.logic.requiredLatency)
  else:
    discard

dispatcher.onTransportEvent = proc(plugin: AudioPlugin, event: TransportEvent) =
  let plugin = CsCorrector(plugin)
  if IsPlaying in event.flags:
    plugin.wasPlaying = plugin.isPlaying
    plugin.isPlaying = true
  else:
    plugin.wasPlaying = plugin.isPlaying
    plugin.isPlaying = false
    # Reset the CsCorrector logic on playback stop
    if plugin.wasPlaying and not plugin.isPlaying:
      plugin.logic.reset()

dispatcher.onMidiEvent = proc(plugin: AudioPlugin, event: MidiEvent) =
  let plugin = CsCorrector(plugin)

  # Don't process when project is not playing back so there isn't
  # an annoying delay when drawing notes on the piano roll
  if not plugin.isPlaying:
    plugin.sendMidiEvent(event)
    return

  let msg = event.data
  let statusCode = msg[0] and 0xF0

  let isNoteOff = statusCode == 0x80
  if isNoteOff:
    plugin.logic.processNoteOff(event.time, int(msg[1]), int(msg[2]))
    return

  let isNoteOn = statusCode == 0x90
  if isNoteOn:
    plugin.logic.processNoteOn(event.time, int(msg[1]), int(msg[2]))
    return

  let isCc = statusCode == 0xB0
  let isHoldPedal = isCc and msg[1] == 64
  if isHoldPedal:
    let isHeld = msg[2] > 63
    plugin.logic.processHoldPedal(isHeld)
    # Don't return because we need to send the hold pedal information

  # Pass any events that aren't note on or off straight to the host
  var event = event
  event.time += plugin.latency
  plugin.sendMidiEvent(event)

dispatcher.onProcess = proc(plugin: AudioPlugin, frameCount: int) =
  # Remove the notes within the frame count from the
  # CsCorrector logic and send them as midi events
  let plugin = CsCorrector(plugin)
  let noteEvents = plugin.logic.extractNoteEvents(frameCount)

  for i in 0 ..< noteEvents.len:
    let noteEvent = noteEvents[i]

    let channel = 0
    var status = channel
    case noteEvent.kind:
      of Off: status += 0x80
      of On: status += 0x90

    plugin.sendMidiEvent(MidiEvent(
      time: noteEvent.time,
      port: 0,
      data: [uint8(status), uint8(noteEvent.key), uint8(noteEvent.velocity)],
    ))

dispatcher.savePreset = proc(plugin: AudioPlugin): seq[byte] =
  return cast[seq[byte]]("1234567890ASDKFOWEFKKADVLOKFAOLDSVKOAKREOFKQOEWFKQOWEFKCDVLSDASV")

dispatcher.loadPreset = proc(plugin: AudioPlugin, data: seq[byte]) =
  plugin.debug(cast[string](data))