import std/algorithm
import ./binding
import ./shared
import ./extensions/latency
import ./extensions/noteports
import ./extensions/parameters
import ./extensions/timer

proc getInstance*(plugin: ptr clap_plugin_t): AudioPlugin =
  return cast[AudioPlugin](plugin.plugin_data)

proc pluginInit*(plugin: ptr clap_plugin_t): bool {.cdecl.} =
  let instance = plugin.getInstance()
  instance.parameterLock.initLock()
  instance.mainThreadParameterValue.setLen(instance.parameterCount)
  instance.mainThreadParameterChanged.setLen(instance.parameterCount)
  instance.audioThreadParameterValue.setLen(instance.parameterCount)
  instance.audioThreadParameterChanged.setLen(instance.parameterCount)
  for i in 0 ..< instance.parameterCount:
    instance.mainThreadParameterValue[i] = instance.info.parameterInfo[i].defaultValue
    instance.audioThreadParameterValue[i] = instance.info.parameterInfo[i].defaultValue
  return true

proc pluginDestroy*(plugin: ptr clap_plugin_t) {.cdecl.} =
  let instance = plugin.getInstance()
  instance.parameterLock.deinitLock()
  GcUnref(instance)

proc pluginActivate*(plugin: ptr clap_plugin_t, sample_rate: cdouble, min_frames_count, max_frames_count: uint32): bool {.cdecl.} =
  let instance = plugin.getInstance()
  instance.isActive = true
  instance.sampleRate = sampleRate
  return true

proc pluginDeactivate*(plugin: ptr clap_plugin_t) {.cdecl.} =
  let instance = plugin.getInstance()
  instance.isActive = false

proc pluginStartProcessing*(plugin: ptr clap_plugin_t): bool {.cdecl.} =
  return true

proc pluginStopProcessing*(plugin: ptr clap_plugin_t) {.cdecl.} =
  discard

proc pluginReset*(plugin: ptr clap_plugin_t) {.cdecl.} =
  discard

proc pluginProcess*(plugin: ptr clap_plugin_t, process: ptr clap_process_t): clap_process_status {.cdecl.} =
  let instance = plugin.getInstance()

  let frameCount = process.frames_count
  let eventCount = process.in_events.size(process.in_events)
  var eventIndex = 0'u32
  var nextEventIndex = if eventCount > 0: 0'u32 else: frameCount
  var frame = 0'u32

  instance.syncParametersMainThreadToAudioThread(process.out_events)

  while frame < frameCount:
    while eventIndex < eventCount and nextEventIndex == frame:
      let eventHeader = process.in_events.get(process.in_events, eventIndex)
      if eventHeader.time != frame:
        nextEventIndex = eventHeader.time
        break

      if eventHeader.space_id == CLAP_CORE_EVENT_SPACE_ID:
        case eventHeader.`type`:
        of CLAP_EVENT_PARAM_VALUE:
          let event = cast[ptr clap_event_param_value_t](eventHeader)
          instance.handleParameterValueEvent(event)

        of CLAP_EVENT_MIDI:
          let event = cast[ptr clap_event_midi_t](eventHeader)
          if instance.info.onMidiEvent != nil:
            instance.info.onMidiEvent(instance, MidiEvent(
              time: int(eventHeader.time),
              port: int(event.portIndex),
              data: event.data,
            ))

        else:
          discard

      eventIndex += 1

      if eventIndex == eventCount:
        nextEventIndex = frameCount
        break

    frame = nextEventIndex

  # Sort output midi events.
  instance.outputMidiEvents.sort do (x, y: MidiEvent) -> int:
    cmp(x.time, y.time)

  # Send output midi events.
  for i in 0 ..< instance.outputMidiEvents.len:
    let event = instance.outputMidiEvents[i]
    var clapEvent = clap_event_midi_t(
      header: clap_event_header_t(
        size: uint32(sizeof(clap_event_midi_t)),
        time: uint32(event.time),
        spaceId: CLAP_CORE_EVENT_SPACE_ID,
        `type`: CLAP_EVENT_MIDI,
        flags: 0,
      ),
      portIndex: uint16(event.port),
      data: event.data,
    )
    discard process.out_events.try_push(process.out_events, addr(clapEvent.header))
  instance.outputMidiEvents.setLen(0)

  return CLAP_PROCESS_CONTINUE

proc pluginOnMainThread*(plugin: ptr clap_plugin_t) {.cdecl.} =
  discard

proc pluginGetExtension*(plugin: ptr clap_plugin_t, id: cstring): pointer {.cdecl.} =
  # if id == CLAP_EXT_GUI: return addr(guiExtension)
  if id == CLAP_EXT_LATENCY: return addr(latencyExtension)
  if id == CLAP_EXT_NOTE_PORTS: return addr(noteportsExtension)
  if id == CLAP_EXT_PARAMS: return addr(parametersExtension)
  if id == CLAP_EXT_TIMER_SUPPORT: return addr(timerExtension)
  return nil