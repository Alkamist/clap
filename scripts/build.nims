import os

const clapDir = getHomeDir() / "AppData" / "Local" / "Programs" / "Common" / "CLAP"

cd thisDir()
cd ".."

proc buildPlugin =
  let opts = [
    "--app:lib",
    "--debugger:native",
    "--gc:arc",
    "--noMain",
    "--o:gain.clap",
    "--outdir:" & clapDir,
  ]

  var optStr = ""
  for opt in opts:
    optStr.add opt
    optStr.add " "

  exec "nimble c " & optStr & "gainplugin.nim"

proc launchReaper =
  let
    reaperDir = "C:" / "Program Files" / "REAPER (x64)"
    reaperFile = reaperDir / "reaper".toExe

  if not reaperDir.dirExists: raise newException(OSError, "Could not find Reaper directory: " & reaperDir)
  if not reaperFile.fileExists: raise newException(OSError, "Could not find Reaper file: " & reaperFile)

  discard gorgeEx reaperFile

buildPlugin()
launchReaper()

# cd clapDir
# exec "gdb gain.clap"