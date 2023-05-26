{.experimental: "codeReordering".}

import std/options
import notequeue as nq
import audioplugin as ap

const channelCount* = nq.channelCount
const delayCount* = 4

type
  CsCorrectorLogic* = ref object
    noteQueue*: NoteQueue
    isPlaying*: bool
    wasPlaying*: bool
    heldKey*: array[channelCount, Option[int]]
    holdPedalIsVirtuallyHeld*: array[channelCount, bool]
    holdPedalIsPhysicallyHeld*: array[channelCount, bool]
    legatoFirstNoteDelay*: int
    legatoDelayTimes*: array[delayCount, int]
    legatoDelayVelocities*: array[delayCount, float]

proc requiredLatency*(logic: CsCorrectorLogic): int =
  var latency = logic.legatoFirstNoteDelay
  for delay in logic.legatoDelayTimes:
    if delay < latency:
      latency = delay
  return -min(0, latency)

proc reset*(logic: CsCorrectorLogic) =
  logic.noteQueue.reset()
  for i in 0 ..< channelCount:
    logic.heldKey[i] = none(int)
    logic.holdPedalIsVirtuallyHeld[i] = false
    logic.holdPedalIsPhysicallyHeld[i] = false

proc processTransportEvent*(logic: CsCorrectorLogic, event: TransportEvent) =
  if IsPlaying in event.flags:
    logic.wasPlaying = logic.isPlaying
    logic.isPlaying = true
  else:
    logic.wasPlaying = logic.isPlaying
    logic.isPlaying = false
    # Reset the note queue on playback stop.
    if logic.wasPlaying and not logic.isPlaying:
      logic.reset()

proc processMidiEvent*(logic: CsCorrectorLogic, event: MidiEvent) =
  # Don't process when project is not playing back so there isn't
  # an annoying delay when drawing notes on the piano roll
  if not logic.isPlaying:
    logic.sendMidiEvent(event)
    return

  let msg = event.data
  let statusCode = msg[0] and 0xF0
  let channel = int(msg[0] and 0x0F)

  let isNoteOff = statusCode == 0x80
  if isNoteOff:
    logic.processNoteOff(event.time, channel, int(msg[1]), float(msg[2]))
    return

  let isNoteOn = statusCode == 0x90
  if isNoteOn:
    logic.processNoteOn(event.time, channel, int(msg[1]), float(msg[2]))
    return

  let isCc = statusCode == 0xB0
  let isHoldPedal = isCc and msg[1] == 64
  if isHoldPedal:
    let isHeld = msg[2] > 63
    logic.processHoldPedal(channel, isHeld)
    # Don't return because we need to send the hold pedal information

  # Pass any events that aren't note on or off straight to the host
  var event = event
  event.time += logic.requiredLatency
  logic.sendMidiEvent(event)

proc sendNoteEvents*(logic: CsCorrectorLogic, plugin: AudioPlugin, frameCount: int) =
  for event in logic.noteQueue.extractEvents(frameCount):
    plugin.sendMidiEvent(event.toMidiEvent())

proc processNoteOn(logic: CsCorrectorLogic, time, channel, key: int, velocity: float) =
  var delay = logic.requiredLatency

  if logic.heldKey[channel].isSome or logic.holdPedalIsVirtuallyHeld[channel]:
    var velocityBottom = 0.0
    for i, velocityTop in logic.legatoDelayVelocities:
      if velocity > velocityBottom and velocity <= velocityTop:
        delay += logic.legatoDelayTimes[i]
        break
      velocityBottom = velocityTop
  else:
    delay += logic.legatoFirstNoteDelay

  logic.heldKey[channel] = some(key)

  logic.noteQueue.addEvent(nq.NoteEvent(
    kind: On,
    time: time + delay,
    channel: channel,
    key: key,
    velocity: velocity,
  ))

  # The virtual hold pedal waits to activate until after the first note on
  if logic.holdPedalIsPhysicallyHeld[channel]:
    logic.holdPedalIsVirtuallyHeld[channel] = true

proc processNoteOff(logic: CsCorrectorLogic, time, channel, key: int, velocity: float) =
  if logic.heldKey[channel].isSome and logic.heldKey[channel].get == key:
    logic.heldKey[channel] = none(int)
  logic.noteQueue.addEvent(nq.NoteEvent(
    kind: Off,
    time: time + logic.requiredLatency,
    channel: channel,
    key: key,
    velocity: velocity,
  ))

proc processHoldPedal(logic: CsCorrectorLogic, channel: int, isHeld: bool) =
  logic.holdPedalIsPhysicallyHeld[channel] = isHeld
  if isHeld:
    # Only hold down the virtual hold pedal if there is already a key held
    if logic.heldKey[channel].isSome:
      logic.holdPedalIsVirtuallyHeld[channel] = true
  else:
    # The virtual hold pedal is always released with the real one
    logic.holdPedalIsVirtuallyHeld[channel] = false

proc toMidiEvent(noteEvent: nq.NoteEvent): ap.MidiEvent =
  var status = noteEvent.channel
  case noteEvent.kind:
    of Off: status += 0x80
    of On: status += 0x90
  return MidiEvent(
    time: noteEvent.time,
    port: 0,
    data: [uint8(status), uint8(noteEvent.key), uint8(noteEvent.velocity)],
  )