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
    &"[{event.data.kind}, {event.time}, {event.isSent}]"

proc `$`*(note: Note): string =
  if note.off.isSome:
    &"Note[{$note.on}, {$note.off.get}]"
  else:
    &"Note[{$note.on}, None]"

proc isSent*(note: Note): bool =
  note.off.isSome and note.off.get.isSent

# proc requiredLatency*(cs: CsCorrector): int =
#   return -min(min(min(min(min(
#     0,
#     cs.legatoDelayFirst),
#     cs.legatoDelayLevel0),
#     cs.legatoDelayLevel1),
#     cs.legatoDelayLevel2),
#     cs.legatoDelayLevel3,
#   )

proc requiredLatency*(cs: CsCorrector): int =
  return 48000

proc startNote(cs: CsCorrector, noteOn: Event) =
  let key = noteOn.data.key

  var delay = 0
  if cs.heldKey.isSome:
    delay = cs.legatoDelayLevel0
  else:
    delay = cs.legatoDelayFirst

  cs.heldKey = some(key)

  noteOn.time += cs.requiredLatency + delay
  var insertIndex = 0
  for i, note in cs.notes[key]:
    if noteOn.time > note.on.time:
      insertIndex = i
  cs.notes[key].insert(Note(on: noteOn, off: none(Event)), insertIndex)
  # cs.notes[key].add(Note(on: noteOn, off: none(Event)))

proc finishNote(cs: CsCorrector, noteOff: Event) =
  let key = noteOff.data.key

  if cs.heldKey.isSome and key == cs.heldKey.get:
    cs.heldKey = none(uint8)

  noteOff.time += cs.requiredLatency

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
    event.time += cs.requiredLatency
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

# proc fixNoteOverlaps(cs: CsCorrector, note: Note) =
#   if note.off.isNone:
#     return

#   let key = note.on.data.key
#   cs.notes[key].sort do (x, y: Note) -> int:
#     cmp(x.on.time, y.on.time)

#   for bufferNote in cs.notes[key]:
#     if note == bufferNote:
#       continue
#     if note.off.get.time > bufferNote.on.time:
#       note.off.get.time = bufferNote.on.time

  # if note.off.get.time < note.on.time:
  #   note.off.get.time = note.on.time

proc pushEvents*(cs: CsCorrector, frameCount: int, pushProc: proc(event: Event)) =
  let sortedEvents = cs.getSortedEvents()
  for event in sortedEvents:
    if event.time < frameCount:
      if not event.isSent:
        event.isSent = true
        pushProc(event)
    else:
      break

  cs.removeSentEvents()

  # for key in 0 ..< 128:
  #   # cs.notes[key].sort do (x, y: Note) -> int:
  #   #   cmp(x.on.time, y.on.time)
  #   for i in 1 ..< cs.notes[key].len:
  #     let prevNote = cs.notes[key][i - 1]
  #     let note = cs.notes[key][i]
  #     if prevNote.off.get.time > note.on.time:
        # prevNote.off.get.time = note.on.time

  # for key in 0 ..< 128:
  #   for note in cs.notes[key]:
  #     cs.fixNoteOverlaps(note)

  cs.decreaseEventTimes(frameCount)

  # for event in cs.otherEvents:
  #   print($event)

  var notesExist = false
  for key in 0 ..< 128:
    for note in cs.notes[key]:
      notesExist = true
      debugString &= $note

  if not notesExist:
    debugString = ""