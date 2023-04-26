type
  Message* = array[3, uint8]

  MessageKind* = enum
    Unknown
    NoteOff
    NoteOn
    Aftertouch
    Cc
    PatchChange
    ChannelPressure
    PitchBend
    NonMusical

proc kind*(msg: Message): MessageKind =
  let statusCode = msg[0] and 0xF0
  case statusCode:
  of 0x80: return NoteOff
  of 0x90: return NoteOn
  of 0xA0: return Aftertouch
  of 0xB0: return Cc
  of 0xC0: return PatchChange
  of 0xD0: return ChannelPressure
  of 0xE0: return PitchBend
  of 0xF0: return NonMusical
  else: return Unknown

proc channel*(msg: Message): uint8 = return min(msg[0] and 0x0F, 15)
proc key*(msg: Message): uint8 = return min(msg[1], 127)
proc velocity*(msg: Message): uint8 = return min(msg[2], 127)
proc ccNumber*(msg: Message): uint8 = return min(msg[1], 127)
proc ccValue*(msg: Message): uint8 = return min(msg[2], 127)