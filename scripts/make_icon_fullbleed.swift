#!/usr/bin/env swift
import AppKit

// macOS 26 (Tahoe) 向けフルブリードアイコン。
// 角まで塗り、自前の角丸/余白/影は入れない（システムが角丸マスク・背景・影を付ける）。
// 確認用に「システム相当の squircle マスク」をかけたプレビューも生成する。
let OUT = "assets/icons"
let SIZE: CGFloat = 1024
let TL = (0x5B5BF0 as UInt32, 0x3A2FB8 as UInt32)
let BR = (0xFFB13C as UInt32, 0xF0891E as UInt32)

func squircle(_ rect: CGRect, n: Double = 5) -> NSBezierPath {
    let p = NSBezierPath()
    let a = rect.width/2, b = rect.height/2, cx = rect.midX, cy = rect.midY
    let steps = 720
    for i in 0...steps {
        let t = Double(i)/Double(steps)*2 * .pi
        let ct = cos(t), st = sin(t)
        let x = cx + a*CGFloat(copysign(pow(abs(ct), 2.0/n), ct))
        let y = cy + b*CGFloat(copysign(pow(abs(st), 2.0/n), st))
        if i == 0 { p.move(to: CGPoint(x:x,y:y)) } else { p.line(to: CGPoint(x:x,y:y)) }
    }
    p.close(); return p
}
func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex>>16)&0xff)/255, green: CGFloat((hex>>8)&0xff)/255, blue: CGFloat(hex&0xff)/255, alpha: 1)
}
func drawCentered(_ s: String, font: NSFont, color c: NSColor, center: CGPoint) {
    let astr = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: c])
    let line = CTLineCreateWithAttributedString(astr)
    let b = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    astr.draw(at: CGPoint(x: center.x - b.midX, y: center.y - b.midY))
}
func named(_ n: String, _ size: CGFloat) -> NSFont { NSFont(name: n, size: size) ?? NSFont.systemFont(ofSize: size, weight: .bold) }

func render(_ size: CGFloat, _ draw: (CGContext)->Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                              colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ctx
    draw(ctx.cgContext); NSGraphicsContext.restoreGraphicsState(); return rep
}
func save(_ rep: NSBitmapImageRep, _ name: String) {
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(OUT)/\(name)"))
    print("wrote \(OUT)/\(name)")
}

// フルブリード本体。off=文字中心の外寄り係数, en/jp=フォントサイズ。
func iconFB(off: CGFloat, enSize: CGFloat, jpSize: CGFloat) -> NSBitmapImageRep {
    render(SIZE) { _ in
        let r = CGRect(x: 0, y: 0, width: SIZE, height: SIZE)
        NSGradient(starting: color(TL.0), ending: color(TL.1))!.draw(in: r, angle: -90)
        let tri = NSBezierPath()
        tri.move(to: CGPoint(x: r.maxX, y: r.minY)); tri.line(to: CGPoint(x: r.minX, y: r.minY))
        tri.line(to: CGPoint(x: r.maxX, y: r.maxY)); tri.close()
        NSGradient(starting: color(BR.0), ending: color(BR.1))!.draw(in: tri, angle: -45)
        let l = NSBezierPath(); l.move(to: CGPoint(x: r.minX, y: r.minY)); l.line(to: CGPoint(x: r.maxX, y: r.maxY))
        l.lineWidth = 16; NSColor.white.withAlphaComponent(0.95).setStroke(); l.stroke()
        let en = named("HelveticaNeue-Bold", enSize)
        let jp = named("Hiragino Sans W6", jpSize)
        drawCentered("A", font: en, color: .white, center: CGPoint(x: SIZE*(1-off), y: SIZE*off))
        drawCentered("あ", font: jp, color: .white, center: CGPoint(x: SIZE*off, y: SIZE*(1-off)))
    }
}

// Tahoe 相当の squircle マスク＋影をかけたプレビュー（カード上に配置）。
func preview(_ full: NSBitmapImageRep, side: CGFloat) -> NSBitmapImageRep {
    let canvas = side * 1.18
    return render(canvas) { _ in
        color(0xF2F2F4).setFill(); NSBezierPath(rect: CGRect(x:0,y:0,width:canvas,height:canvas)).fill()
        let m = (canvas - side)/2
        let rect = CGRect(x: m, y: m, width: side, height: side)
        let mask = squircle(rect, n: 5)
        NSGraphicsContext.saveGraphicsState()
        let sh = NSShadow(); sh.shadowColor = NSColor.black.withAlphaComponent(0.25)
        sh.shadowBlurRadius = side*0.05; sh.shadowOffset = NSSize(width: 0, height: -side*0.02); sh.set()
        NSColor.white.setFill(); mask.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.saveGraphicsState(); mask.addClip()
        let img = NSImage(size: NSSize(width: SIZE, height: SIZE)); img.addRepresentation(full)
        img.draw(in: rect)
        NSGraphicsContext.restoreGraphicsState()
    }
}

let cands: [(String, CGFloat, CGFloat, CGFloat, String)] = [
    ("icon-fb-narrow.png", 0.615, 430, 390, "余白 小（文字大）"),
    ("icon-fb-mid.png",    0.635, 400, 360, "余白 中"),
    ("icon-fb-wide.png",   0.655, 370, 335, "余白 大（文字小）"),
]
var previews: [NSBitmapImageRep] = []
for (f, off, en, jp, _) in cands {
    let rep = iconFB(off: off, enSize: en, jpSize: jp); save(rep, f)
    previews.append(preview(rep, side: 360))
}

// 比較シート（マスク済みプレビューを横並び）
let cell = previews[0].size.width, pad: CGFloat = 24, label: CGFloat = 56
let sw = cell*CGFloat(previews.count)+pad*CGFloat(previews.count+1), shh = cell+pad*2+label
let s = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(sw), pixelsHigh: Int(shh),
                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let sctx = NSGraphicsContext(bitmapImageRep: s)!
NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = sctx
color(0xEDEDEF).setFill(); NSBezierPath(rect: CGRect(x:0,y:0,width:sw,height:shh)).fill()
for (i, p) in previews.enumerated() {
    let x = pad + (cell+pad)*CGFloat(i)
    let img = NSImage(size: p.size); img.addRepresentation(p)
    img.draw(in: CGRect(x: x, y: pad+label, width: cell, height: cell))
    let str = NSAttributedString(string: cands[i].4, attributes: [
        .font: NSFont.systemFont(ofSize: 26, weight: .semibold), .foregroundColor: color(0x333333)])
    str.draw(at: CGPoint(x: x + (cell-str.size().width)/2, y: 18))
}
NSGraphicsContext.restoreGraphicsState()
save(s, "_contact-sheet-fullbleed.png")
print("done")
