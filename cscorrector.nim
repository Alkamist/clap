import std/options
import std/algorithm
import midi

var print*: proc(x: string)

type
  Note* = ref object
    on*: Event
    off*: Event

  Event* = ref object
    time*: int
    data*: midi.Message

  CsCorrector* = ref object
    events*: seq[Event]
    notes*: array[128, seq[Note]]
    currentNote*: Note
    heldKey*: Option[uint8]
    legatoDelayFirst*: int # Freshly pressed key
    legatoDelayLevel0*: int # Lowest velocity legato
    legatoDelayLevel1*: int
    legatoDelayLevel2*: int
    legatoDelayLevel3*: int # Highest velocity legato

proc requiredLatency*(cs: CsCorrector): int =
  return -min(min(min(min(min(
    0,
    cs.legatoDelayFirst),
    cs.legatoDelayLevel0),
    cs.legatoDelayLevel1),
    cs.legatoDelayLevel2),
    cs.legatoDelayLevel3,
  )

# proc printNotes(cs: CsCorrector, key: uint8) =
#   var output = ""
#   for note in cs.notes[key]:
#     output = output & $note[]
#   print(output)

# proc printEvents(cs: CsCorrector) =
#   var output = ""
#   for event in cs.events:
#     output = output & $event[]
#   print(output)

proc processEvent*(cs: CsCorrector, event: Event) =
  var delay = 0

  case event.data.kind:
  of NoteOff:
      let key = event.data.key

      if cs.heldKey.isSome and key == cs.heldKey.get:
        cs.heldKey = none(uint8)

      if cs.currentNote != nil:
        cs.currentNote.off = event
        cs.currentNote = nil

      # cs.printEvents()

  of NoteOn:
      let key = event.data.key

      if cs.heldKey.isSome:
        delay = cs.legatoDelayLevel0
      else:
        delay = cs.legatoDelayFirst

      cs.heldKey = some(key)

      cs.currentNote = Note(on: event)
      cs.notes[key].add(cs.currentNote)

      # cs.printEvents()

  else:
    discard

  event.time += cs.requiredLatency + delay
  if event.time < 0:
    event.time = 0

  cs.events.add(event)

proc sortEventsByTime(cs: CsCorrector) =
  cs.events.sort do (x, y: Event) -> int:
    cmp(x.time, y.time)

proc stillHasEvent(cs: CsCorrector, event: Event): bool =
  if event == nil:
    return false
  for bufferEvent in cs.events:
    if event == bufferEvent:
      return true

proc removeInactiveNotes(cs: CsCorrector) =
  for key, keyNotes in cs.notes:
    var keepNotes: seq[Note]
    for note in keyNotes:
      if cs.stillHasEvent(note.off):
        keepNotes.add(note)
    cs.notes[key] = keepNotes

proc pushEvents*(cs: CsCorrector, frameCount: int, pushProc: proc(event: Event)) =
  cs.sortEventsByTime()

  var keepEvents: seq[Event]

  for event in cs.events:
    if event.time < frameCount:
      pushProc(event)
    else:
      keepEvents.add(event)

  cs.events = keepEvents

  cs.removeInactiveNotes()

  for event in cs.events:
    event.time -= frameCount