import AppKit
let url = URL(fileURLWithPath: CommandLine.arguments[1])
guard let image = NSImage(contentsOf: url), let data = image.tiffRepresentation,
      let png = NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
