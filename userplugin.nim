import std/tables; export tables
import clap
import cscorrector
import nimgui; export nimgui
import oswindow; export oswindow

var debugStringChanged* = false
var debugString* = ""

type
  UserPlugin* = ref object
    gui*: Gui
    window*: OsWindow
    csCorrector*: CsCorrector
    clapHost*: ptr clap.Host
    clapPlugin*: clap.Plugin
    sampleRate*: float
    latency*: int
    midiPort*: int
    timerNameToIdTable*: Table[string, clap.Id]
    timerIdToProcTable*: Table[clap.Id, proc()]

proc millisToSamples*(plugin: UserPlugin, millis: float): int =
  int(millis * plugin.sampleRate * 0.001)

proc getUserPlugin*(clapPlugin: ptr clap.Plugin): UserPlugin =
  cast[UserPlugin](clapPlugin.pluginData)

proc print*(x: string) =
  debugString = debugString & x & "\n"
  debugStringChanged = true