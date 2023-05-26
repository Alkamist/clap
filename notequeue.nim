import std/options

const keyCount* = 128
const channelCount* = 16

type
  NoteEventKind* = enum
    Off
    On

  NoteEvent* = object
    kind*: NoteEventKind
    time*: int
    channel*: int
    key*: int
    velocity*: float

  NoteQueue* = ref object
    playhead*: int
    noteEvents*: seq[NoteEvent]
    lastEventSent*: array[channelCount, array[keyCount, Option[NoteEvent]]]
    pendingNoteOffCount*: array[channelCount, array[keyCount, int]]

proc new*(_: typedesc[NoteQueue], capacity: int): NoteQueue =
  return NoteQueue(noteEvents: newSeqOfCap[NoteEvent](capacity))

proc reset*(nq: NoteQueue) =
  nq.playhead = 0
  nq.noteEvents.setLen(0)
  for channel in 0 ..< channelCount:
    for key in 0 ..< keyCount:
      nq.lastEventSent[channel][key] = none(NoteEvent)
      nq.pendingNoteOffCount[channel][key] = 0

proc addEvent*(nq: NoteQueue, event: NoteEvent) =
  var event = event
  event.time += nq.playhead

  let count = nq.noteEvents.len

  # Insert events sorted by time.
  if count == 0:
    nq.noteEvents.add(event)
  else:
    for i in 0 ..< count:
      if event.time < nq.noteEvents[i].time:
        nq.noteEvents.insert(event, i)
        break
      if i == count - 1:
        nq.noteEvents.add(event)

iterator extractEvents*(nq: NoteQueue, frameCount: int): NoteEvent {.inline.} =
  var keepPosition = 0

  for i in 0 ..< nq.noteEvents.len:
    let event = nq.noteEvents[i]
    let offset = event.time - nq.playhead

    # Send the event if it is inside the frame count.
    if offset < frameCount:
      let channel = event.channel
      let key = event.key

      let lastEvent = nq.lastEventSent[channel][key]
      if lastEvent.isSome:
        # If two note-ons in a row are detected,
        # send a note off first to avoid overlaps.
        if lastEvent.get.kind == On and event.kind == On:
          yield NoteEvent(
            kind: Off,
            time: offset,
            channel: channel,
            key: key,
            velocity: 0.0,
          )

          nq.lastEventSent[channel][key] = some(event)
          nq.pendingNoteOffCount[channel][key] += 1

      # Always send note-ons, but ignore lingering note-offs that
      # were sent early because of a note-on overlap.
      if event.kind == On or nq.pendingNoteOffCount[channel][key] == 0:
        yield NoteEvent(
          kind: event.kind,
          time: offset,
          channel: channel,
          key: key,
          velocity: event.velocity,
        )

        nq.lastEventSent[channel][key] = some(event)
      else:
        nq.pendingNoteOffCount[channel][key] -= 1
        if nq.pendingNoteOffCount[channel][key] < 0:
          nq.pendingNoteOffCount[channel][key] = 0

    # Keep the event otherwise.
    else:
      if keepPosition != i:
        nq.noteEvents[keepPosition] = event
      keepPosition += 1

  nq.noteEvents.setLen(keepPosition)

  # Increment the playhead if there are no events, otherwise reset it.
  if nq.noteEvents.len > 0:
    nq.playhead += frameCount
  else:
    nq.playhead = 0