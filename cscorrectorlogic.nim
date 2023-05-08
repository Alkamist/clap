{.experimental: "codeReordering".}

import std/options
import std/algorithm
import std/sequtils

const keyCount = 128

type
  NoteEventKind* = enum
    On
    Off

  Note* = ref object
    on*: NoteEvent
    off*: Option[NoteEvent]

  NoteEvent* = object
    kind*: NoteEventKind
    time*: int
    key*: int
    velocity*: int
    isSent*: bool

  CsCorrectorLogic* = ref object
    notes*: array[keyCount, seq[Note]]
    heldKey*: Option[int]
    legatoFirstNoteDelay*: int
    legatoPortamentoDelay*: int
    legatoSlowDelay*: int
    legatoMediumDelay*: int
    legatoFastDelay*: int

proc requiredLatency*(cs: CsCorrectorLogic): int =
  return -min(min(min(min(min(
    0,
    cs.legatoFirstNoteDelay),
    cs.legatoPortamentoDelay),
    cs.legatoSlowDelay),
    cs.legatoMediumDelay),
    cs.legatoFastDelay,
  ) * 2

proc reset*(cs: CsCorrectorLogic) =
  cs.heldKey = none(int)
  for key in 0 ..< keyCount:
    cs.notes[key].setLen(0)

proc startNote*(cs: CsCorrectorLogic, time, key, velocity: int) =
  var delay = 0

  if cs.heldKey.isSome:
    if velocity <= 20:
      delay = cs.legatoPortamentoDelay
    elif velocity > 20 and velocity <= 64:
      delay = cs.legatoSlowDelay
    elif velocity > 64 and velocity <= 100:
      delay = cs.legatoMediumDelay
    else:
      delay = cs.legatoFastDelay
  else:
    delay = cs.legatoFirstNoteDelay

  cs.heldKey = some(key)

  let noteEvent = NoteEvent(
    kind: On,
    time: time + cs.requiredLatency + delay,
    key: key,
    velocity: velocity,
  )

  cs.notes[key].add(Note(on: noteEvent, off: none(NoteEvent)))

proc finishNote*(cs: CsCorrectorLogic, time, key, velocity: int) =
  if cs.heldKey.isSome and key == cs.heldKey.get:
    cs.heldKey = none(int)

  let noteEvent = NoteEvent(
    kind: Off,
    time: time + cs.requiredLatency,
    key: key,
    velocity: velocity,
  )

  for i in 0 ..< cs.notes[key].len:
    let note = cs.notes[key][i]
    if note.off.isNone:
      note.off = some(noteEvent)

proc extractNoteEvents*(cs: CsCorrectorLogic, frameCount: int): seq[NoteEvent] =
  let sortedEvents = cs.getSortedEvents()
  for event in sortedEvents:
    if event.time < frameCount - cs.requiredLatency:
      if not event.isSent:
        event.isSent = true
        result.add(event)
    else:
      break
  cs.removeSentEvents()
  cs.fixNoteOverlaps()
  cs.decreaseEventTimes(frameCount)

proc isSent(note: Note): bool =
  note.off.isSome and note.off.get.isSent

# proc getSortedNoteEvents(cs: CsCorrectorLogic): seq[NoteEvent] =
#   for key in 0 ..< keyCount:
#     for i in 0 ..< cs.notes[key].len:
#       let note = cs.notes[key][i]
#       if not note.on.isSent:
#         result.add(note.on)
#       if note.off.isSome and not note.off.get.isSent:
#         result.add(note.off.get)
#   result.sort do (x, y: Event) -> int:
#     cmp(x.time, y.time)

proc removeSentEvents(cs: CsCorrectorLogic) =
  for key in 0 ..< keyCount:
    cs.notes[key].keepItIf(not it.isSent)

proc decreaseEventTimes(cs: CsCorrectorLogic, frameCount: int) =
  for key in 0 ..< keyCount:
    for i in 0 ..< cs.notes[key].len:
      let note = cs.notes[key][i]
      note.on.time -= frameCount
      if note.off.isSome:
        note.off.get.time -= frameCount

proc fixNoteOverlaps(cs: CsCorrectorLogic) =
  for key in 0 ..< keyCount:
    var sortedNotes = cs.notes[key]

    sortedNotes.sort do (x, y: Note) -> int:
      cmp(x.on.time, y.on.time)

    for i in 1 ..< sortedNotes.len:
      var prevNote = sortedNotes[i - 1]
      var note = sortedNotes[i]
      if prevNote.off.isSome and prevNote.off.get.time > note.on.time:
        prevNote.off.get.time = note.on.time
        if prevNote.off.get.time < prevNote.on.time:
          prevNote.off.get.time = prevNote.on.time

# type
#   MidiMessage = array[3, uint8]

#   MidiMessageKind = enum
#     Unknown
#     NoteOff
#     NoteOn
#     Aftertouch
#     Cc
#     PatchChange
#     ChannelPressure
#     PitchBend
#     NonMusical

# proc kind(msg: MidiMessage): MidiMessageKind =
#   let statusCode = msg[0] and 0xF0
#   return case statusCode:
#     of 0x80: NoteOff
#     of 0x90: NoteOn
#     of 0xA0: Aftertouch
#     of 0xB0: Cc
#     of 0xC0: PatchChange
#     of 0xD0: ChannelPressure
#     of 0xE0: PitchBend
#     of 0xF0: NonMusical
#     else: Unknown

# proc channel(msg: MidiMessage): uint8 = return min(msg[0] and 0x0F, 15)
# proc key(msg: MidiMessage): uint8 = return min(msg[1], 127)
# proc velocity(msg: MidiMessage): uint8 = return min(msg[2], 127)
# proc ccNumber(msg: MidiMessage): uint8 = return min(msg[1], 127)
# proc ccValue(msg: MidiMessage): uint8 = return min(msg[2], 127)