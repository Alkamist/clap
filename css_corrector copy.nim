# import std/locks
import audioplugin

type
  CssCorrectorParameter = enum
    LegatoFirstNoteDelay
    LegatoPortamentoDelay
    LegatoSlowDelay
    LegatoMediumDelay
    LegatoFastDelay

  CssCorrector = ref object of AudioPlugin
    isPlaying: bool
    wasPlaying: bool
    # debugStringMutex: Lock
    # debugString: string
    # debugStringChanged: bool
    # logic*: CsCorrectorLogic

proc init(plugin: CssCorrector) =
  # var reaperPluginInfo := cast[ptr reaper_plugin_info_t]plugin.clap_host->get_extension("cockos.reaper_extension")
  # reaper.load_functions(reaperPluginInfo)

  # plugin.registerTimer("DebugTimer", 0, proc(plugin: AudioPlugin) =
  #   if plugin.debugStringChanged:
  #     plugin.debugStringMutex.acquire()
  #     reaper.showConsoleMsg(cstring(plugin.debugString))
  #     plugin.debugString = ""
  #     plugin.debugStringChanged = false
  #     plugin.debugStringMutex.release()
  # )

  # plugin.logic.plugin = plugin
  # plugin.logic.note_queue = nq.create(0, 1024)
  # plugin.logic.legato_delay_velocities[0] = 20
  # plugin.logic.legato_delay_velocities[1] = 64
  # plugin.logic.legato_delay_velocities[2] = 100
  # plugin.logic.legato_delay_velocities[3] = 128
  # plugin.updateLogicParameters()

  discard

proc destroy(plugin: CssCorrector) =
  # plugin.unregisterTimer("DebugTimer")
  discard

proc activate(plugin: CssCorrector) =
  # plugin.updateLogicParameters()
  discard

proc deactivate(plugin: CssCorrector) =
  discard

proc reset(plugin: CssCorrector) =
  # plugin.logic.reset()
  discard

proc onParameterEvent(plugin: CssCorrector, event: ParameterEvent) =
  # plugin.updateLogicParameters()
  discard

proc onTransportEvent(plugin: CssCorrector, event: TransportEvent) =
  # plugin.logic.processTransportEvent(event)
  discard

proc onMidiEvent(plugin: CssCorrector, event: MidiEvent) =
  # plugin.logic.processMidiEvent(event)
  discard

proc onProcess(plugin: CssCorrector, frameCount: int) =
  # plugin.logic.sendNoteEvents(frameCount)
  discard

proc savePreset(plugin: CssCorrector): string =
  return ""

proc loadPreset(plugin: CssCorrector, data: openArray[byte]) =
  # plugin.updateLogicParameters()
  discard

# debug :: proc(plugin: CssCorrector, arg: any) {
#     msg := fmt.aprint(arg)
#     defer delete(msg)
#     msg_with_newline := strings.concatenate({msg, "\n"})
#     defer delete(msg_with_newline)
#     sync.lock(&plugin.debug_string_mutex)
#     strings.write_string(&plugin.debug_string_builder, msg_with_newline)
#     plugin.debug_string_changed = true
#     sync.unlock(&plugin.debug_string_mutex)
# }

# proc updateLogicParameters(plugin: CssCorrector) =
#   plugin.logic.legatoFirstNoteDelay = milliseconds_to_samples(plugin, parameter(plugin, .Legato_First_Note_Delay))
#   plugin.logic.legatoDelayTimes[0] = milliseconds_to_samples(plugin, parameter(plugin, .Legato_Portamento_Delay))
#   plugin.logic.legatoDelayTimes[1] = milliseconds_to_samples(plugin, parameter(plugin, .Legato_Slow_Delay))
#   plugin.logic.legatoDelayTimes[2] = milliseconds_to_samples(plugin, parameter(plugin, .Legato_Medium_Delay))
#   plugin.logic.legatoDelayTimes[3] = milliseconds_to_samples(plugin, parameter(plugin, .Legato_Fast_Delay))
#   set_latency(plugin, required_latency(&plugin.logic))

proc makeParam*(id: CssCorrectorParameter, name: string, defaultValue: float): ParameterInfo =
  result.id = int(id)
  result.name = name
  result.minValue = -500.0
  result.maxValue = 500.0
  result.defaultValue = defaultValue
  result.flags = {IsAutomatable}
  result.module = ""

# exportClapPlugin(
#   plugin = CssCorrector,
#   parameters = CssCorrectorParameter,

#   id = "com.alkamist.CssCorrector",
#   name = "Css Corrector",
#   vendor = "Alkamist Audio",
#   url = "",
#   manualUrl = "",
#   supportUrl = "",
#   version = "0.1.0",
#   description = "A MIDI timing corrector for Cinematic Studio Strings.",

#   onCreate = onCreate,
#   onDestroy = onDestroy,
#   onActivate = onActivate,
#   onDeactivate = onDeactivate,
#   onReset = onReset,
#   onParameterEvent = onParameterEvent,
#   onTransportEvent = onTransportEvent,
#   onMidiEvent = onMidiEvent,
#   onProcess = onProcess,
#   savePreset = savePreset,
#   loadPreset = loadPreset,

#   parameterInfo = [
#     makeParam(LegatoFirstNoteDelay, "Legato First Note Delay", -60.0),
#     makeParam(LegatoPortamentoDelay, "Legato Portamento Delay", -300.0),
#     makeParam(LegatoSlowDelay, "Legato Slow Delay", -300.0),
#     makeParam(LegatoMediumDelay, "Legato Medium Delay", -300.0),
#     makeParam(LegatoFastDelay, "Legato Fast Delay", -150.0),
#   ],
# )