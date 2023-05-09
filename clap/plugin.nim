import std/algorithm
import ./binding
import ./shared
import ./extensions/latency
import ./extensions/noteports
import ./extensions/parameters
import ./extensions/reaper
import ./extensions/state
import ./extensions/timer

proc pluginInit*(plugin: ptr clap_plugin_t): bool {.cdecl.} =
  let instance = plugin.getInstance()

  instance.parameterLock.initLock()

  instance.mainThreadParameterValue.setLen(instance.parameterCount)
  instance.mainThreadParameterChanged.setLen(instance.parameterCount)
  instance.audioThreadParameterValue.setLen(instance.parameterCount)
  instance.audioThreadParameterChanged.setLen(instance.parameterCount)

  for i in 0 ..< instance.parameterCount:
    instance.mainThreadParameterValue[i] = instance.dispatcher.parameterInfo[i].defaultValue
    instance.audioThreadParameterValue[i] = instance.dispatcher.parameterInfo[i].defaultValue

  instance.clapHostLog = cast[ptr clap_host_log_t](instance.clapHost.get_extension(instance.clapHost, CLAP_EXT_LOG))
  instance.clapHostLatency = cast[ptr clap_host_latency_t](instance.clapHost.get_extension(instance.clapHost, CLAP_EXT_LATENCY))
  instance.clapHostTimerSupport = cast[ptr clap_host_timer_support_t](instance.clapHost.get_extension(instance.clapHost, CLAP_EXT_TIMER_SUPPORT))

  if instance.dispatcher.onCreateInstance != nil:
    instance.dispatcher.onCreateInstance(instance)

  instance.registerTimer("Debug", 0, proc(plg: AudioPlugin) =
    if plg.debugStringChanged:
      reaper.showConsoleMsg(cstring(plg.debugString))
      plg.debugString = ""
      plg.debugStringChanged = false
  )

  return true

proc pluginDestroy*(plugin: ptr clap_plugin_t) {.cdecl.} =
  let instance = plugin.getInstance()
  instance.unregisterTimer("Debug")
  if instance.dispatcher.onDestroyInstance != nil:
    instance.dispatcher.onDestroyInstance(instance)
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

  # Dispatch the transport event
  let clapTransportEvent = process.transport
  if clapTransportEvent != nil:
    if instance.dispatcher.onTransportEvent != nil:
      var event = TransportEvent()

      if (clapTransportEvent.flags and CLAP_TRANSPORT_IS_PLAYING) != 0:
        event.flags.incl(IsPlaying)

      if (clapTransportEvent.flags and CLAP_TRANSPORT_IS_RECORDING) != 0:
        event.flags.incl(IsRecording)

      if (clapTransportEvent.flags and CLAP_TRANSPORT_IS_LOOP_ACTIVE) != 0:
        event.flags.incl(LoopIsActive)

      if (clapTransportEvent.flags and CLAP_TRANSPORT_IS_WITHIN_PRE_ROLL) != 0:
        event.flags.incl(IsWithinPreRoll)

      if (clapTransportEvent.flags and CLAP_TRANSPORT_HAS_TIME_SIGNATURE) != 0:
        event.timeSignature = some(TimeSignature(
          numerator: int(clapTransportEvent.tsig_num),
          denominator: int(clapTransportEvent.tsig_denom),
        ))

      if (clapTransportEvent.flags and CLAP_TRANSPORT_HAS_TEMPO) != 0:
        event.tempo = some(clapTransportEvent.tempo)
        event.tempoIncrement = some(clapTransportEvent.tempo_inc)

      if (clapTransportEvent.flags and CLAP_TRANSPORT_HAS_BEATS_TIMELINE) != 0:
        event.songPositionBeats = some(int(clapTransportEvent.song_pos_beats) / CLAP_BEATTIME_FACTOR)
        event.loopStartBeats = some(int(clapTransportEvent.loop_start_beats) / CLAP_BEATTIME_FACTOR)
        event.loopEndBeats = some(int(clapTransportEvent.loop_end_beats) / CLAP_BEATTIME_FACTOR)
        event.barStartBeats = some(int(clapTransportEvent.bar_start) / CLAP_BEATTIME_FACTOR)
        event.barNumber = some(int(clapTransportEvent.bar_number))

      if (clapTransportEvent.flags and CLAP_TRANSPORT_HAS_SECONDS_TIMELINE) != 0:
        event.songPositionSeconds = some(int(clapTransportEvent.song_pos_seconds) / CLAP_SECTIME_FACTOR)
        event.loopStartSeconds = some(int(clapTransportEvent.loop_start_seconds) / CLAP_SECTIME_FACTOR)
        event.loopEndSeconds = some(int(clapTransportEvent.loop_end_seconds) / CLAP_SECTIME_FACTOR)

      instance.dispatcher.onTransportEvent(instance, event)

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
          if instance.dispatcher.onMidiEvent != nil:
            instance.dispatcher.onMidiEvent(instance, MidiEvent(
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

  if instance.dispatcher.onProcess != nil:
    instance.dispatcher.onProcess(instance, int(process.frames_count))

  # Sort and send output midi events
  instance.outputMidiEvents.sort do (x, y: MidiEvent) -> int:
    cmp(x.time, y.time)
  for i in 0 ..< instance.outputMidiEvents.len:
    let event = instance.outputMidiEvents[i]
    var clapEvent = clap_event_midi_t(
      header: clap_event_header_t(
        size: uint32(sizeof(clap_event_midi_t)),
        time: uint32(event.time - instance.latency),
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
  if id == CLAP_EXT_STATE: return addr(stateExtension)
  return nil