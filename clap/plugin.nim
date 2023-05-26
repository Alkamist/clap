import std/algorithm
import ./binding
import ./common

proc fromBeatTime(time: clap_beat_time): float =
  return int(time) / CLAP_BEATTIME_FACTOR

proc fromSecTime(time: clap_sec_time): float =
  return int(time) / CLAP_SECTIME_FACTOR

proc dispatchTransportEvent[T](plugin: T, clapEvent: ptr clap_event_transport_t) =
  mixin onTransportEvent

  if clapEvent != nil:
    var event = TransportEvent()

    if (clapEvent.flags and CLAP_TRANSPORT_IS_PLAYING) != 0:
      event.flags.incl(IsPlaying)

    if (clapEvent.flags and CLAP_TRANSPORT_IS_RECORDING) != 0:
      event.flags.incl(IsRecording)

    if (clapEvent.flags and CLAP_TRANSPORT_IS_LOOP_ACTIVE) != 0:
      event.flags.incl(LoopIsActive)

    if (clapEvent.flags and CLAP_TRANSPORT_IS_WITHIN_PRE_ROLL) != 0:
      event.flags.incl(IsWithinPreRoll)

    if (clapEvent.flags and CLAP_TRANSPORT_HAS_TIME_SIGNATURE) != 0:
      event.timeSignature = some(TimeSignature(
        numerator: int(clapEvent.tsig_num),
        denominator: int(clapEvent.tsig_denom),
      ))

    if (clapEvent.flags and CLAP_TRANSPORT_HAS_TEMPO) != 0:
      event.tempo = some(clapEvent.tempo)
      event.tempoIncrement = some(clapEvent.tempo_inc)

    if (clapEvent.flags and CLAP_TRANSPORT_HAS_BEATS_TIMELINE) != 0:
      event.songPositionBeats = some(fromBeatTime(clapEvent.song_pos_beats))
      event.loopStartBeats = some(fromBeatTime(clapEvent.loop_start_beats))
      event.loopEndBeats = some(fromBeatTime(clapEvent.loop_end_beats))
      event.barStartBeats = some(fromBeatTime(clapEvent.bar_start))
      event.barNumber = some(int(clapEvent.bar_number))

    if (clapEvent.flags and CLAP_TRANSPORT_HAS_SECONDS_TIMELINE) != 0:
      event.songPositionSeconds = some(fromSecTime(clapEvent.song_pos_seconds))
      event.loopStartSeconds = some(fromSecTime(clapEvent.loop_start_seconds))
      event.loopEndSeconds = some(fromSecTime(clapEvent.loop_end_seconds))

    plugin.onTransportEvent(event)

proc dispatchMidiEvent[T](plugin: T, eventHeader: ptr clap_event_header_t) =
  mixin onMidiEvent
  var clapEvent = cast[ptr clap_event_midi_t](eventHeader)
  plugin.onMidiEvent(MidiEvent(
    time: int(event_header.time),
    port: int(clap_event.port_index),
    data: clap_event.data,
  ))

proc pluginInit*[T](plugin: ptr clap_plugin_t): bool {.cdecl.} =
  mixin init
  let plugin = cast[T](plugin.plugin_data)

  for i in 0 ..< plugin.parameterValues.len:
    plugin.resetParameterToDefault(i)

  # plugin.clap_host_log = cast(^Clap_Host_Log)(plugin.clap_host->get_extension(CLAP_EXT_LOG))
  plugin.clapHostTimerSupport = cast[ptr clap_host_timer_support_t](plugin.clapHost.get_extension(plugin.clapHost, CLAP_EXT_TIMER_SUPPORT))
  plugin.clapHostLatency = cast[ptr clap_host_latency_t](plugin.clapHost.get_extension(plugin.clapHost, CLAP_EXT_LATENCY))
  plugin.outputEvents = newSeqOfCap[clap_event_midi_t](16384)

  plugin.init()

  return true

proc pluginDestroy*[T](plugin: ptr clap_plugin_t) {.cdecl.} =
  mixin destroy
  let plugin = cast[T](plugin.plugin_data)
  plugin.destroy()
  GcUnRef(plugin)

proc pluginActivate*[T](plugin: ptr clap_plugin_t, sample_rate: float, min_frames_count, max_frames_count: uint32): bool {.cdecl.} =
  mixin activate
  let plugin = cast[T](plugin.plugin_data)

  plugin.sampleRate = sample_rate
  plugin.minFrameCount = int(min_frames_count)
  plugin.maxFrameCount = int(max_frames_count)
  plugin.isActive = true

  plugin.activate()

  return true

proc pluginDeactivate*[T](plugin: ptr clap_plugin_t) {.cdecl.} =
  mixin deactivate
  let plugin = cast[T](plugin.plugin_data)
  plugin.isActive = false
  plugin.deactivate()

proc pluginStartProcessing*(plugin: ptr clap_plugin_t): bool {.cdecl.} =
  return true

proc pluginStopProcessing*(plugin: ptr clap_plugin_t) {.cdecl.} =
  discard

proc pluginReset*[T](plugin: ptr clap_plugin_t) {.cdecl.} =
  mixin reset
  let plugin = cast[T](plugin.plugin_data)
  plugin.outputEvents.setLen(0)
  plugin.reset()

proc pluginProcess*[T](plugin: ptr clap_plugin_t, clapProcess: ptr clap_process_t): clap_process_status {.cdecl.} =
  mixin onProcess

  let plugin = cast[T](plugin.plugin_data)

  let frameCount = clapProcess.frames_count
  let eventCount = clapProcess.in_events.size(clapProcess.in_events)
  var eventIndex: uint32 = 0
  var nextEventIndex: uint32 = 0
  if eventCount == 0:
    nextEventIndex = frameCount

  var frame: uint32 = 0

  plugin.dispatchTransportEvent(clapProcess.transport)

  while frame < frameCount:
    while eventIndex < eventCount and nextEventIndex == frame:
      var eventHeader = clapProcess.in_events.get(clapProcess.in_events, eventIndex)
      if eventHeader.time != frame:
        nextEventIndex = eventHeader.time
        break

      if eventHeader.space_id == CLAP_CORE_EVENT_SPACE_ID:
        plugin.dispatchParameterEvent(eventHeader)
        plugin.dispatchMidiEvent(eventHeader)

      eventIndex += 1

      if eventIndex == eventCount:
        nextEventIndex = frameCount
        break

    # Audio processing will happen here eventually.

    frame = nextEventIndex

  plugin.onProcess(int(clapProcess.frames_count))

  # Sort and send output events, then clear the buffer.
  plugin.outputEvents.sort do (x, y: clap_event_midi_t) -> int:
    cmp(x.header.time, y.header.time)
  for event in plugin.outputEvents:
    var event = event
    discard clapProcess.out_events.try_push(clapProcess.out_events, cast[ptr clap_event_header_t](addr(event)))

  plugin.outputEvents.setLen(0)

  return CLAP_PROCESS_CONTINUE

proc pluginOnMainThread*(plugin: ptr clap_plugin_t) {.cdecl.} =
  discard