import clap

type
  PluginInfo* {.bycopy.} = object
    callerVersion*: cint
    hwndMain*: pointer
    register*: proc(name: cstring, infoStruct: pointer): cint {.cdecl.}
    getFunc*: proc(name: cstring): pointer {.cdecl.}

var showConsoleMsg*: proc(msg: cstring) {.cdecl.}
var showMessageBox*: proc(msg: cstring, title: cstring, `type`: cint): cint {.cdecl.}

proc getReaperPluginInfo(clapHost: ptr clap.Host): ptr PluginInfo =
  cast[ptr PluginInfo](clapHost.getExtension(clapHost, "cockos.reaper_extension"))

proc loadFunctions*(clapHost: ptr clap.Host) =
  var reaperPluginInfo = clapHost.getReaperPluginInfo()
  showConsoleMsg = cast[typeof(showConsoleMsg)](reaperPluginInfo.getFunc("ShowConsoleMsg"))
  showMessageBox = cast[typeof(showMessageBox)](reaperPluginInfo.getFunc("ShowMessageBox"))