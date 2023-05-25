type
  reaper_plugin_info_t* {.bycopy.} = object
    caller_version*: cint
    hwnd_main*: pointer
    Register*: proc(name: cstring, infostruct: pointer): cint {.cdecl.}
    GetFunc*: proc(name: cstring): pointer {.cdecl.}

var ShowConsoleMsg*: proc(msg: cstring) {.cdecl.}

proc loadFunctions*(pluginInfo: ptr reaper_plugin_info_t) =
  if pluginInfo == nil:
    return
  ShowConsoleMsg = cast[typeof(ShowConsoleMsg)](pluginInfo.GetFunc("ShowConsoleMsg"))