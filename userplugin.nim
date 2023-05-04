import std/tables; export tables
import clap
import cscorrector
import ./oswindow; export oswindow
import ./vectorgraphics; export vectorgraphics

type
  UserPlugin* = ref object
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

proc millisToSamples*(plugin: UserPlugin, millis: float): int =
  int(millis * plugin.sampleRate * 0.001)

proc getUserPlugin*(clapPlugin: ptr clap.Plugin): UserPlugin =
  cast[UserPlugin](clapPlugin.pluginData)