{.experimental: "overloadableEnums".}

import opengl
import std/unicode; export unicode
import ./vectorgraphics/nanovg

type
  Winding* = enum
    CounterClockwise
    Clockwise

  PathWinding* = enum
    CounterClockwise
    Clockwise
    Solid
    Hole

  LineCap* = enum
    Butt
    Round
    Square

  LineJoin* = enum
    Round
    Bevel
    Miter

  TextAlignX* = enum
    Left
    Center
    Right

  TextAlignY* = enum
    Top
    Center
    Bottom
    Baseline

  Glyph* = object
    index*: uint64
    x*: float
    minX*, maxX*: float

  VectorGraphics* = ref object
    ctx*: NVGcontext

proc `=destroy`*(vg: var type VectorGraphics()[]) =
  nvgDelete(vg.ctx)

{.push inline.}

proc new*(T: type VectorGraphics): VectorGraphics =
  return VectorGraphics(ctx: nvgCreate(NVG_ANTIALIAS or NVG_STENCIL_STROKES))

proc toNVGEnum(winding: Winding): cint =
  return case winding:
    of CounterClockwise: NVG_CCW
    of Clockwise: NVG_CW

proc toNVGEnum(winding: PathWinding): cint =
  return case winding:
    of CounterClockwise: NVG_CCW
    of Clockwise: NVG_CW
    of Solid: NVG_SOLID
    of Hole: NVG_HOLE

proc toNVGEnum(cap: LineCap): cint =
  return case cap:
    of Butt: NVG_BUTT
    of Round: NVG_ROUND
    of Square: NVG_SQUARE

proc toNVGEnum(join: LineJoin): cint =
  return case join:
    of Round: NVG_ROUND
    of Bevel: NVG_BEVEL
    of Miter: NVG_MITER

proc beginFrame*(vg: VectorGraphics, width, height: int, pixelDensity: float) =
  nvgBeginFrame(vg.ctx, float(width) / pixelDensity, float(height) / pixelDensity, pixelDensity)
  nvgResetScissor(vg.ctx)

proc endFrame*(vg: VectorGraphics, width, height: int) =
  glEnable(GL_BLEND)
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
  glEnable(GL_STENCIL_TEST)
  glEnable(GL_SCISSOR_TEST)
  glViewport(0, 0, int32(width), int32(height))
  glScissor(0, 0, int32(width), int32(height))
  glClear(GL_STENCIL_BUFFER_BIT)
  nvgEndFrame(vg.ctx)

proc beginPath*(vg: VectorGraphics) = nvgBeginPath(vg.ctx)
proc moveTo*(vg: VectorGraphics, x, y: float) = nvgMoveTo(vg.ctx, x, y)
proc lineTo*(vg: VectorGraphics, x, y: float) = nvgLineTo(vg.ctx, x, y)
proc quadTo*(vg: VectorGraphics, cx, cy, x, y: float) = nvgQuadTo(vg.ctx, cx, cy, x, y)
proc arcTo*(vg: VectorGraphics, x0, y0, x1, y1, radius: float) = nvgArcTo(vg.ctx, x0, y0, x1, y1, radius)
proc closePath*(vg: VectorGraphics) = nvgClosePath(vg.ctx)
proc arc*(vg: VectorGraphics, cx, cy, r, a0, a1: float, winding: Winding) = nvgArc(vg.ctx, cx, cy, r, a0, a1, winding.toNVGEnum())
proc rect*(vg: VectorGraphics, x, y, width, height: float) = nvgRect(vg.ctx, x, y, width, height)
proc roundedRect*(vg: VectorGraphics, x, y, width, height, radius: float) = nvgRoundedRect(vg.ctx, x, y, width, height, radius)
proc roundedRect*(vg: VectorGraphics, x, y, width, height, radTopLeft, radTopRight, radBottomRight, radBottomLeft: float) = nvgRoundedRectVarying(vg.ctx, x, y, width, height, radTopLeft, radTopRight, radBottomRight, radBottomLeft)
proc ellipse*(vg: VectorGraphics, cx, cy, rx, ry: float) = nvgEllipse(vg.ctx, cx, cy, rx, ry)
proc circle*(vg: VectorGraphics, cx, cy, r: float) = nvgCircle(vg.ctx, cx, cy, r)
proc fill*(vg: VectorGraphics) = nvgFill(vg.ctx)
proc stroke*(vg: VectorGraphics) = nvgStroke(vg.ctx)
proc saveState*(vg: VectorGraphics) = nvgSave(vg.ctx)
proc restoreState*(vg: VectorGraphics) = nvgRestore(vg.ctx)
proc reset*(vg: VectorGraphics) = nvgReset(vg.ctx)

proc setPathWinding*(vg: VectorGraphics, winding: PathWinding) = nvgPathWinding(vg.ctx, winding.toNVGEnum())
proc setShapeAntiAlias*(vg: VectorGraphics, enabled: bool) = nvgShapeAntiAlias(vg.ctx, cint(enabled))
proc setStrokeColor*(vg: VectorGraphics, r, g, b, a: float) = nvgStrokeColor(vg.ctx, NVGcolor(r: r, g: g, b: b, a: a))
# proc setStrokePaint*(vg: VectorGraphics, paint: Paint) = nvgStrokePaint(vg, paint)
proc setFillColor*(vg: VectorGraphics, r, g, b, a: float) = nvgFillColor(vg.ctx, NVGcolor(r: r, g: g, b: b, a: a))
# proc setFillPaint*(vg: VectorGraphics, paint: Paint) = nvgFillPaint(vg, paint)
proc setMiterLimit*(vg: VectorGraphics, limit: float) = nvgMiterLimit(vg.ctx, limit)
proc setStrokeWidth*(vg: VectorGraphics, width: float) = nvgStrokeWidth(vg.ctx, width)
proc setLineCap*(vg: VectorGraphics, cap: LineCap) = nvgLineCap(vg.ctx, cap.toNVGEnum())
proc setLineJoin*(vg: VectorGraphics, join: LineJoin) = nvgLineJoin(vg.ctx, join.toNVGEnum())
proc setGlobalAlpha*(vg: VectorGraphics, alpha: float) = nvgGlobalAlpha(vg.ctx, alpha)

proc clip*(vg: VectorGraphics, x, y, width, height: float, intersect = true) =
  if intersect:
    nvgIntersectScissor(vg.ctx, x, y, width, height)
  else:
    nvgScissor(vg.ctx, x, y, width, height)

proc resetClip*(vg: VectorGraphics) = nvgResetScissor(vg.ctx)

proc addFont*(vg: VectorGraphics, name, data: string) =
  let font = nvgCreateFontMem(vg.ctx, cstring(name), cstring(data), cint(data.len), 0)
  if font == -1:
    echo "Failed to load font: " & name

proc drawText*(vg: VectorGraphics, x, y: float, text: openArray[char]): float {.discardable.} =
  if text.len <= 0:
    return
  return nvgText(
    vg.ctx,
    x, y,
    cast[cstring](unsafeAddr(text[0])),
    cast[cstring](cast[uint64](unsafeAddr(text[text.len - 1])) + 1),
  )

proc drawTextBox*(vg: VectorGraphics, x, y, width: float, text: openArray[char]) =
  if text.len <= 0:
    return
  nvgTextBox(
    vg.ctx,
    x, y, width,
    cast[cstring](unsafeAddr(text[0])),
    cast[cstring](cast[uint64](unsafeAddr(text[text.len - 1])) + 1),
  )

proc textMetrics*(vg: VectorGraphics): tuple[ascender, descender, lineHeight: float32] =
  nvgTextMetrics(vg.ctx, addr(result.ascender), addr(result.descender), addr(result.lineHeight))

proc setTextAlign*(vg: VectorGraphics, x: TextAlignX, y: TextAlignY) =
  let nvgXValue = case x:
    of Left: NVG_ALIGN_LEFT
    of Center: NVG_ALIGN_CENTER
    of Right: NVG_ALIGN_RIGHT
  let nvgYValue = case y:
    of Top: NVG_ALIGN_TOP
    of Center: NVG_ALIGN_MIDDLE
    of Bottom: NVG_ALIGN_BOTTOM
    of Baseline: NVG_ALIGN_BASELINE
  nvgTextAlign(vg.ctx, cint(nvgXValue or nvgYValue))

proc setFont*(vg: VectorGraphics, name: string) = nvgFontFace(vg.ctx, cstring(name))
proc setFontSize*(vg: VectorGraphics, size: float) = nvgFontSize(vg.ctx, size)
proc setLetterSpacing*(vg: VectorGraphics, spacing: float) = nvgTextLetterSpacing(vg.ctx, spacing)
proc translate*(vg: VectorGraphics, x, y: float) = nvgTranslate(vg.ctx, x, y)
proc scale*(vg: VectorGraphics, x, y: float) = nvgScale(vg.ctx, x, y)

{.pop.}

# template width*(glyph: Glyph): auto = glyph.maxX - glyph.minX

# proc getGlyphs*(vg: VectorGraphics, position: Vec2, text: openArray[char]): seq[Glyph] =
#   if text.len <= 0:
#     return

#   var nvgPositions = newSeq[NVGglyphPosition](text.len)
#   discard nvgTextGlyphPositions(vg, position.x, position.y, cast[cstring](text[0].unsafeAddr), nil, nvgPositions[0].addr, text.len.cint)
#   for i in countdown(nvgPositions.len - 1, 0, 1):
#     let glyph = nvgPositions[i]
#     if glyph.str != nil:
#       nvgPositions.setLen(i + 1)
#       break

#   result.setLen(nvgPositions.len)
#   for i, nvgPosition in nvgPositions:
#     result[i].index = cast[uint64](nvgPosition.str) - cast[uint64](text[0].unsafeAddr)
#     result[i].x = nvgPosition.x
#     result[i].minX = nvgPosition.minx
#     result[i].maxX = nvgPosition.maxx