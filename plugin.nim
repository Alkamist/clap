{.experimental: "overloadableEnums".}

import clap
import userplugin
import extensions
import cscorrector

var descriptor* = clap.PluginDescriptor(
  clapVersion: clap.Version(major: 1, minor: 1, revision: 7),
  id: "com.alkamist.cs_corrector",
  name: "Cs Corrector",
  vendor: "Alkamist Audio",
  url: "",
  manualUrl: "",
  supportUrl: "",
  version: "0.1.0",
  description: "",
)

proc init(clapPlugin: ptr clap.Plugin): bool {.cdecl.} =
  let plugin = clapPlugin.getUserPlugin()
  plugin.parameterLock.initLock()
  plugin.csCorrector = CsCorrector()
  for id in ParameterId:
    plugin.mainThreadParameterValue[id] = parameterInfo[id].defaultValue
    plugin.audioThreadParameterValue[id] = parameterInfo[id].defaultValue
  return true

proc destroy(clapPlugin: ptr clap.Plugin) {.cdecl.} =
  let plugin = clapPlugin.getUserPlugin()
  plugin.parameterLock.deinitLock()
  plugin.csCorrector.reset()
  GcUnref(plugin)

proc activate(clapPlugin: ptr clap.Plugin, sampleRate: float64, minFramesCount, maxFramesCount: uint32): bool {.cdecl.} =
  let plugin = clapPlugin.getUserPlugin()
  plugin.isActive = true
  plugin.sampleRate = sampleRate
  plugin.updateCsCorrectorParameters()
  return true

proc deactivate(clapPlugin: ptr clap.Plugin) {.cdecl.} =
  let plugin = clapPlugin.getUserPlugin()
  plugin.isActive = false
  plugin.csCorrector.reset()

proc startProcessing(clapPlugin: ptr clap.Plugin): bool {.cdecl.} =
  return true

proc stopProcessing(clapPlugin: ptr clap.Plugin) {.cdecl.} =
  discard

proc reset(clapPlugin: ptr clap.Plugin) {.cdecl.} =
  let plugin = clapPlugin.getUserPlugin()
  plugin.csCorrector.reset()

proc process(clapPlugin: ptr clap.Plugin, clapProcess: ptr clap.Process): clap.ProcessStatus {.cdecl.} =
  let plugin = clapPlugin.getUserPlugin()

  let frameCount = clapProcess.framesCount
  let eventCount = clapProcess.inEvents.size(clapProcess.inEvents)
  var eventIndex = 0'u32
  var nextEventIndex = if eventCount > 0: 0'u32 else: frameCount
  var frame = 0'u32

  parameters.syncMainThreadToAudioThread(plugin, clapProcess.outEvents)

  # let transportEvent = clapProcess.transport
  # if transportEvent != nil:
  #   let flags = cast[set[TransportFlags]](transportEvent.flags)
  #   if IsPlaying in flags:
  #     plugin.isPlaying = true
  #     plugin.setLatency(plugin.csCorrector.requiredLatency)
  #   else:
  #     plugin.isPlaying = false
      # plugin.csCorrector.reset()
      # plugin.setLatency(0)

  while frame < frameCount:
    while eventIndex < eventCount and nextEventIndex == frame:
      let eventHeader = clapProcess.inEvents.get(clapProcess.inEvents, eventIndex)
      if eventHeader.time != frame:
        nextEventIndex = eventHeader.time
        break

      if eventHeader.space_id == clap.coreEventSpaceId:
        case eventHeader.`type`:
        of EventType.ParamValue:
          let event = cast[ptr clap.EventParamValue](eventHeader)
          plugin.handleEventParamValue(event)

        of EventType.Midi:
          let event = cast[ptr clap.EventMidi](eventHeader)
          if event.portIndex == uint16(plugin.midiPort):
            plugin.csCorrector.processEvent(cscorrector.Event(
              time: int(event.header.time),
              data: event.data,
            ))

          # var clapEvent = clap.EventMidi(
          #   header: clap.EventHeader(
          #     size: uint32(sizeOf(clap.EventMidi)),
          #     time: eventHeader.time - uint32(plugin.latency),
          #     spaceId: clap.coreEventSpaceId,
          #     `type`: EventType.Midi,
          #     flags: 0,
          #   ),
          #   portIndex: uint16(plugin.midiPort),
          #   data: event.data,
          # )
          # discard clapProcess.outEvents.tryPush(clapProcess.outEvents, addr(clapEvent.header))

        else:
          discard

      eventIndex += 1

      if eventIndex == eventCount:
        nextEventIndex = frameCount
        break

    frame = nextEventIndex

  plugin.csCorrector.pushEvents(int(frameCount), proc(event: cscorrector.Event) =
    var clapEvent = clap.EventMidi(
      header: clap.EventHeader(
        size: uint32(sizeof(clap.EventMidi)),
        time: uint32(event.time),
        spaceId: clap.coreEventSpaceId,
        `type`: EventType.Midi,
        flags: 0,
      ),
      portIndex: uint16(plugin.midiPort),
      data: event.data,
    )
    discard clapProcess.outEvents.tryPush(clapProcess.outEvents, addr(clapEvent.header))
  )

  return Continue

proc getExtension(clapPlugin: ptr clap.Plugin, id: cstring): pointer {.cdecl.} =
  # if id == clap.extGui: return addr(gui.extension)
  if id == clap.extLatency: return addr(latency.extension)
  if id == clap.extNotePorts: return addr(noteports.extension)
  if id == clap.extParams: return addr(parameters.extension)
  if id == clap.extTimerSupport: return addr(timer.extension)

proc onMainThread(clapPlugin: ptr clap.Plugin) {.cdecl.} =
  discard

proc createInstance*(host: ptr clap.Host): ptr clap.Plugin =
  let plugin = UserPlugin()
  GcRef(plugin)
  plugin.clapHost = host
  plugin.clapPlugin = clap.Plugin(
    desc: addr(descriptor),
    pluginData: cast[pointer](plugin),
    init: init,
    destroy: destroy,
    activate: activate,
    deactivate: deactivate,
    startProcessing: startProcessing,
    stopProcessing: stopProcessing,
    reset: reset,
    process: process,
    getExtension: getExtension,
    onMainThread: onMainThread,
  )
  return addr(plugin.clapPlugin)