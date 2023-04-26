import std/tables; export tables
import clap
import cscorrector

var debugString* = ""

type
  UserPlugin* = ref object
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

proc print*(x: varargs[string, `$`]) =
  for msg in x:
    debugString = debugString & msg
  debugString = debugString & "\n"