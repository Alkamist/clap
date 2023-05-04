import std/strformat
import std/options
import std/algorithm
import std/sequtils
import midi

var debugString* = ""

type
  Note* = ref object
    on*: Event
    off*: Option[Event]

  Event* = ref object
    time*: int
    data*: midi.Message
    isSent*: bool

  CsCorrector* = ref object
    otherEvents*: seq[Event]
    notes*: array[128, seq[Note]]
    heldKey*: Option[uint8]
    legatoDelayFirst*: int # Freshly pressed key
    legatoDelayLevel0*: int # Lowest velocity legato
    legatoDelayLevel1*: int
    legatoDelayLevel2*: int
    legatoDelayLevel3*: int # Highest velocity legato

proc `$`*(event: Event): string =
  if event == nil:
    "nil"
  else:
    &"{event.time}"

proc `$`*(note: Note): string =
  if note.off.isSome:
    &"[{$note.on}, {$note.off.get}]"
  else:
    &"[{$note.on}, None]"

proc isSent*(note: Note): bool =
  note.off.isSome and note.off.get.isSent

proc requiredLatency*(cs: CsCorrector): int =
  return -min(min(min(min(min(
    0,
    cs.legatoDelayFirst),
    cs.legatoDelayLevel0),
    cs.legatoDelayLevel1),
    cs.legatoDelayLevel2),
    cs.legatoDelayLevel3,
  ) * 2

# proc requiredLatency*(cs: CsCorrector): int =
#   48000

proc startNote(cs: CsCorrector, noteOn: Event) =
  let key = noteOn.data.key

  var delay = 0
  if cs.heldKey.isSome:
    let velocity = noteOn.data.velocity
    if velocity <= 20:
      delay = cs.legatoDelayLevel0
    elif velocity > 20 and velocity <= 64:
      delay = cs.legatoDelayLevel1
    elif velocity > 64 and velocity <= 100:
      delay = cs.legatoDelayLevel2
    else:
      delay = cs.legatoDelayLevel3
  else:
    delay = cs.legatoDelayFirst

  cs.heldKey = some(key)

  # noteOn.time += cs.requiredLatency + delay
  noteOn.time += delay

  cs.notes[key].add(Note(on: noteOn, off: none(Event)))

proc finishNote(cs: CsCorrector, noteOff: Event) =
  let key = noteOff.data.key

  if cs.heldKey.isSome and key == cs.heldKey.get:
    cs.heldKey = none(uint8)

  # noteOff.time += cs.requiredLatency

  for note in cs.notes[key]:
    if note.off.isNone:
      note.off = some(noteOff)

proc reset*(cs: CsCorrector) =
  cs.otherEvents.setLen(0)
  for key in 0 ..< 128:
    cs.notes[key].setLen(0)

proc processEvent*(cs: CsCorrector, event: Event) =
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

proc getSortedEvents(cs: CsCorrector): seq[Event] =
  for event in cs.otherEvents:
    result.add(event)
  for key in 0 ..< 128:
    for note in cs.notes[key]:
      if not note.on.isSent:
        result.add(note.on)
      if note.off.isSome and not note.off.get.isSent:
        result.add(note.off.get)
  result.sort do (x, y: Event) -> int:
    cmp(x.time, y.time)

proc removeSentEvents(cs: CsCorrector) =
  cs.otherEvents.keepItIf(not it.isSent)
  for key in 0 ..< 128:
    cs.notes[key].keepItIf(not it.isSent)

proc decreaseEventTimes(cs: CsCorrector, frameCount: int) =
  for event in cs.otherEvents:
    event.time -= frameCount
  for key in 0 ..< 128:
    for note in cs.notes[key]:
      note.on.time -= frameCount
      if note.off.isSome:
        note.off.get.time -= frameCount

proc fixNoteOverlaps(cs: CsCorrector) =
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

proc pushEvents*(cs: CsCorrector, frameCount: int, pushProc: proc(event: Event)) =
  let sortedEvents = cs.getSortedEvents()
  for event in sortedEvents:
    if event.time < frameCount - cs.requiredLatency:
      if not event.isSent:
        event.isSent = true
        pushProc(event)
    else:
      break

  cs.removeSentEvents()
  cs.fixNoteOverlaps()
  cs.decreaseEventTimes(frameCount)

  # debugString = ""
  # for key in 0 ..< 128:
  #   for note in cs.notes[key]:
  #     debugString &= $note