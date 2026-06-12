// Renders the app icon: soccer ball on a pitch-green gradient squircle.
// Usage: swift make_icon.swift <output.iconset dir>
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func render(_ size: Int) -> NSImage {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()

    let inset = s * 0.05
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let path = NSBezierPath(roundedRect: rect, xRadius: s * 0.21, yRadius: s * 0.21)
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.10, green: 0.45, blue: 0.25, alpha: 1),
        NSColor(calibratedRed: 0.02, green: 0.16, blue: 0.12, alpha: 1),
    ])!
    gradient.draw(in: path, angle: -90)

    let ball = "⚽️" as NSString
    let fontSize = s * 0.52
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: fontSize)]
    let ballSize = ball.size(withAttributes: attrs)
    ball.draw(at: NSPoint(x: (s - ballSize.width) / 2, y: (s - ballSize.height) / 2 + s * 0.06),
              withAttributes: attrs)

    if size >= 128 {
        let label = "2026" as NSString
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: s * 0.13, weight: .heavy),
            .foregroundColor: NSColor.white.withAlphaComponent(0.92),
        ]
        let labelSize = label.size(withAttributes: labelAttrs)
        label.draw(at: NSPoint(x: (s - labelSize.width) / 2, y: s * 0.12), withAttributes: labelAttrs)
    }

    image.unlockFocus()
    return image
}

func write(_ image: NSImage, to path: String) {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: URL(fileURLWithPath: path))
}

let entries: [(Int, String)] = [
    (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png"),
]
for (size, name) in entries {
    write(render(size), to: "\(outDir)/\(name)")
}
print("Wrote iconset to \(outDir)")
