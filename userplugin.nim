{.experimental: "codeReordering".}

import std/tables; export tables
import std/locks; export locks
import clap
import cscorrector
import ./oswindow; export oswindow
import ./vectorgraphics; export vectorgraphics

var debugString* = ""

type
  ParameterId* = enum
    LegatoFirstNoteDelay
    LegatoPortamentoDelay
    LegatoSlowDelay
    LegatoMediumDelay
    LegatoFastDelay

var parameterInfo*: array[ParameterId, ParameterInfo] = [
  ParameterInfo(
    id: LegatoFirstNoteDelay,
    flags: {IsAutomatable},
    name: "Legato First Note Delay",
    module: "",
    minValue: -1000.0,
    maxvalue: 1000.0,
    defaultValue: -60.0,
  ),
  ParameterInfo(
    id: LegatoPortamentoDelay,
    flags: {IsAutomatable},
    name: "Legato Portamento Delay",
    module: "",
    minValue: -1000.0,
    maxvalue: 1000.0,
    defaultValue: -300.0,
  ),
  ParameterInfo(
    id: LegatoSlowDelay,
    flags: {IsAutomatable},
    name: "Legato Slow Delay",
    module: "",
    minValue: -1000.0,
    maxvalue: 1000.0,
    defaultValue: -300.0,
  ),
  ParameterInfo(
    id: LegatoMediumDelay,
    flags: {IsAutomatable},
    name: "Legato Medium Delay",
    module: "",
    minValue: -1000.0,
    maxvalue: 1000.0,
    defaultValue: -300.0,
  ),
  ParameterInfo(
    id: LegatoFastDelay,
    flags: {IsAutomatable},
    name: "Legato Fast Delay",
    module: "",
    minValue: -1000.0,
    maxvalue: 1000.0,
    defaultValue: -150.0,
  ),
]

type
  UserPlugin* = ref object
    isActive*: bool
    isPlaying*: bool
    window*: OsWindow
    vg*: VectorGraphics
    csCorrector*: CsCorrector
    clapHost*: ptr clap.Host
    clapPlugin*: clap.Plugin
    sampleRate*: float
    latency*: int
    midiPort*: int
    timerNameToIdTable*: Table[string, clap.Id]
    timerIdToProcTable*: Table[clap.Id, proc(plugin: UserPlugin)]
    mainThreadParameterValue*: array[ParameterId, float]
    mainThreadParameterChanged*: array[ParameterId, bool]
    audioThreadParameterValue*: array[ParameterId, float]
    audioThreadParameterChanged*: array[ParameterId, bool]
    parameterLock*: locks.Lock

proc updateCsCorrectorParameters*(plugin: UserPlugin) =
  plugin.csCorrector.legatoFirstNoteDelay = plugin.millisToSamples(plugin.parameter(LegatoFirstNoteDelay))
  plugin.csCorrector.legatoPortamentoDelay = plugin.millisToSamples(plugin.parameter(LegatoPortamentoDelay))
  plugin.csCorrector.legatoSlowDelay = plugin.millisToSamples(plugin.parameter(LegatoSlowDelay))
  plugin.csCorrector.legatoMediumDelay = plugin.millisToSamples(plugin.parameter(LegatoMediumDelay))
  plugin.csCorrector.legatoFastDelay = plugin.millisToSamples(plugin.parameter(LegatoFastDelay))
  plugin.setLatency(plugin.csCorrector.requiredLatency)

# ==========================================================
# Utility
# ==========================================================

proc getUserPlugin*(clapPlugin: ptr clap.Plugin): UserPlugin =
  return cast[UserPlugin](clapPlugin.pluginData)

proc millisToSamples*(plugin: UserPlugin, millis: float): int =
  return int(millis * plugin.sampleRate * 0.001)

# ==========================================================
# Latency
# ==========================================================

proc informHostOfLatencyChange*(plugin: UserPlugin) =
  let hostLatency = cast[ptr clap.HostLatency](plugin.clapHost.getExtension(plugin.clapHost, clap.extLatency))
  hostLatency.changed(plugin.clapHost)
  if plugin.isActive:
    plugin.clapHost.requestRestart(plugin.clapHost)

proc setLatency*(plugin: UserPlugin, value: int) =
  plugin.latency = value
  plugin.informHostOfLatencyChange()

# ==========================================================
# Parameters
# ==========================================================

type
  ParameterInfo* = object
    id*: ParameterId
    flags*: set[clap.ParamInfoFlags]
    name*: string
    module*: string
    minValue*: float
    maxValue*: float
    defaultValue*: float

proc parameter*(plugin: UserPlugin, id: ParameterId): float =
  return plugin.audioThreadParameterValue[id]

proc handleEventParamValue*(plugin: UserPlugin, event: ptr clap.EventParamValue) =
  let id = ParameterId(event.paramId)
  plugin.parameterLock.acquire()
  plugin.audioThreadParameterValue[id] = event.value
  plugin.audioThreadParameterChanged[id] = true
  plugin.parameterLock.release()

# ==========================================================
# Timer
# ==========================================================

proc registerTimer*(plugin: UserPlugin, name: string, periodMs: int, timerProc: proc(plugin: UserPlugin)) =
  var id: clap.Id
  let hostTimerSupport = cast[ptr clap.HostTimerSupport](plugin.clapHost.getExtension(plugin.clapHost, clap.extTimerSupport))
  discard hostTimerSupport.registerTimer(plugin.clapHost, uint32(periodMs), id.addr)
  plugin.timerNameToIdTable[name] = id
  plugin.timerIdToProcTable[id] = timerProc

proc unregisterTimer*(plugin: UserPlugin, name: string) =
  if plugin.timerNameToIdTable.hasKey(name):
    let id = plugin.timerNameToIdTable[name]
    let hostTimerSupport = cast[ptr clap.HostTimerSupport](plugin.clapHost.getExtension(plugin.clapHost, clap.extTimerSupport))
    discard hostTimerSupport.unregisterTimer(plugin.clapHost, id)
    plugin.timerIdToProcTable[id] = nil