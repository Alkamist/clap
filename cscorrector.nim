import std/options
import std/algorithm
import midi

var print*: proc(x: varargs[string, `$`])

type
  Note* = ref object
    on*: Event
    off*: Event

  Event* = ref object
    time*: int
    data*: midi.Message

  CsCorrector* = ref object
    events*: seq[Event]
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

proc processEvent*(cs: CsCorrector, event: Event) =
  var delay = 0

  case event.data.kind:
  of NoteOff:
      let key = event.data.key

      if cs.heldKey.isSome and key == cs.heldKey.get:
        cs.heldKey = none(uint8)

  of NoteOn:
      let key = event.data.key

      if cs.heldKey.isSome:
        delay = cs.legatoDelayLevel0
      else:
        delay = cs.legatoDelayFirst

      cs.heldKey = some(key)

  else:
    discard

  event.time += cs.requiredLatency + delay
  if event.time < 0:
    event.time = 0

  cs.events.add(event)

proc sortEventsByTime(cs: CsCorrector) =
  cs.events.sort do (x, y: Event) -> int:
    cmp(x.time, y.time)

proc pushEvents*(cs: CsCorrector, frameCount: int, pushProc: proc(event: Event)) =
  cs.sortEventsByTime()

  var keepEvents: seq[Event]

  for event in cs.events:
    if event.time < frameCount:
      pushProc(event)
    else:
      keepEvents.add(event)

  cs.events = keepEvents

  for event in cs.events:
    event.time -= frameCount