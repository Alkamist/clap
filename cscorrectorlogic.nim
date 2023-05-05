{.experimental: "codeReordering".}

import std/options
import std/algorithm
import std/sequtils

type
  Note* = ref object
    on*: Event
    off*: Option[Event]

  Event* = ref object
    time*: int
    data*: MidiMessage
    isSent*: bool

  CsCorrectorLogic* = ref object
    otherEvents*: seq[Event]
    notes*: array[128, seq[Note]]
    heldKey*: Option[uint8]
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
  cs.heldKey = none(uint8)
  cs.otherEvents.setLen(0)
  for key in 0 ..< 128:
    cs.notes[key].setLen(0)

proc processEvent*(cs: CsCorrectorLogic, event: Event) =
  if event == nil:
    return
  case event.data.kind:
  of NoteOff:
    cs.finishNote(event)
  of NoteOn:
    cs.startNote(event)
  else:
    # event.time += cs.requiredLatency
    cs.otherEvents.add(event)

proc extractEvents*(cs: CsCorrectorLogic, frameCount: int): seq[Event] =
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

proc startNote(cs: CsCorrectorLogic, noteOn: Event) =
  let key = noteOn.data.key

  var delay = 0
  if cs.heldKey.isSome:
    let velocity = noteOn.data.velocity
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

  # noteOn.time += cs.requiredLatency + delay
  noteOn.time += delay

  cs.notes[key].add(Note(on: noteOn, off: none(Event)))

proc finishNote(cs: CsCorrectorLogic, noteOff: Event) =
  let key = noteOff.data.key

  if cs.heldKey.isSome and key == cs.heldKey.get:
    cs.heldKey = none(uint8)

  # noteOff.time += cs.requiredLatency

  for i in 0 ..< cs.notes[key].len:
    let note = cs.notes[key][i]
    if note.off.isNone:
      note.off = some(noteOff)

proc getSortedEvents(cs: CsCorrectorLogic): seq[Event] =
  for i in 0 ..< cs.otherEvents.len:
    let event = cs.otherEvents[i]
    result.add(event)
  for key in 0 ..< 128:
    for i in 0 ..< cs.notes[key].len:
      let note = cs.notes[key][i]
      if not note.on.isSent:
        result.add(note.on)
      if note.off.isSome and not note.off.get.isSent:
        result.add(note.off.get)
  result.sort do (x, y: Event) -> int:
    cmp(x.time, y.time)

proc removeSentEvents(cs: CsCorrectorLogic) =
  cs.otherEvents.keepItIf(not it.isSent)
  for key in 0 ..< 128:
    cs.notes[key].keepItIf(not it.isSent)

proc decreaseEventTimes(cs: CsCorrectorLogic, frameCount: int) =
  for i in 0 ..< cs.otherEvents.len:
    let event = cs.otherEvents[i]
    event.time -= frameCount
  for key in 0 ..< 128:
    for i in 0 ..< cs.notes[key].len:
      let note = cs.notes[key][i]
      note.on.time -= frameCount
      if note.off.isSome:
        note.off.get.time -= frameCount

proc fixNoteOverlaps(cs: CsCorrectorLogic) =
  for key in 0 ..< 128:
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

type
  MidiMessage = array[3, uint8]

  MidiMessageKind = enum
    Unknown
    NoteOff
    NoteOn
    Aftertouch
    Cc
    PatchChange
    ChannelPressure
    PitchBend
    NonMusical

proc kind(msg: MidiMessage): MidiMessageKind =
  let statusCode = msg[0] and 0xF0
  return case statusCode:
    of 0x80: NoteOff
    of 0x90: NoteOn
    of 0xA0: Aftertouch
    of 0xB0: Cc
    of 0xC0: PatchChange
    of 0xD0: ChannelPressure
    of 0xE0: PitchBend
    of 0xF0: NonMusical
    else: Unknown

# proc channel(msg: MidiMessage): uint8 = return min(msg[0] and 0x0F, 15)
proc key(msg: MidiMessage): uint8 = return min(msg[1], 127)
proc velocity(msg: MidiMessage): uint8 = return min(msg[2], 127)
# proc ccNumber(msg: MidiMessage): uint8 = return min(msg[1], 127)
# proc ccValue(msg: MidiMessage): uint8 = return min(msg[2], 127)