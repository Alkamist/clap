import clap

type
  PluginInfo* {.bycopy.} = object
    callerVersion*: cint
    hwndMain*: pointer
    register*: proc(name: cstring, infoStruct: pointer): cint {.cdecl.}
    getFunc*: proc(name: cstring): pointer {.cdecl.}

var showConsoleMsg*: proc(msg: cstring) {.cdecl.}

proc getReaperPluginInfo(clapHost: ptr clap.Host): ptr PluginInfo =
  cast[ptr PluginInfo](clapHost.getExtension(clapHost, "cockos.reaper_extension"))

proc loadFunctions*(clapHost: ptr clap.Host) =
  var reaperPluginInfo = clapHost.getReaperPluginInfo()
  showConsoleMsg = cast[typeOf(showConsoleMsg)](reaperPluginInfo.getFunc("ShowConsoleMsg"))