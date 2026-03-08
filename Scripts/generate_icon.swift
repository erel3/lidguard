#!/usr/bin/env swift

import AppKit
import Foundation

// MARK: - Color Space

let sRGB = CGColorSpaceCreateDeviceRGB()

// MARK: - Icon Drawing

func drawIcon(size: CGFloat) -> NSImage {
  let image = NSImage(size: NSSize(width: size, height: size))
  image.lockFocus()

  guard let ctx = NSGraphicsContext.current?.cgContext else {
    image.unlockFocus()
    return image
  }

  let rect = CGRect(x: 0, y: 0, width: size, height: size)

  drawBackground(ctx: ctx, rect: rect)
  drawSymbol(ctx: ctx, rect: rect)

  image.unlockFocus()
  return image
}

// MARK: - 1. Background

func drawBackground(ctx: CGContext, rect: CGRect) {
  let s = rect.width
  let cornerRadius = s * 0.2237
  let path = CGPath(roundedRect: rect.insetBy(dx: s * 0.01, dy: s * 0.01),
                     cornerWidth: cornerRadius, cornerHeight: cornerRadius,
                     transform: nil)

  ctx.saveGState()
  ctx.addPath(path)
  ctx.clip()

  // Dark burgundy — solid with subtle top-light gradient
  let bgColors = [
    CGColor(red: 0.18, green: 0.06, blue: 0.07, alpha: 1.0),  // #2e1012 top (slightly lighter)
    CGColor(red: 0.10, green: 0.03, blue: 0.04, alpha: 1.0)   // #1a080a bottom (darker)
  ]
  let bgGrad = CGGradient(colorsSpace: sRGB, colors: bgColors as CFArray,
                           locations: [0.0, 1.0])!
  ctx.drawLinearGradient(bgGrad,
                          start: CGPoint(x: s * 0.5, y: s),
                          end: CGPoint(x: s * 0.5, y: 0),
                          options: [])

  ctx.restoreGState()
}

// MARK: - 2. Symbol (one-color laptop + eye)

func drawLaptopShape(ctx: CGContext, cx: CGFloat, s: CGFloat, lineW: CGFloat, fill: Bool) {
  // --- Screen lid (landscape rect, stroked) ---
  let screenW = s * 0.58
  let screenH = s * 0.34
  let screenX = cx - screenW / 2
  let screenY = s * 0.40
  let screenCorner = s * 0.025
  let screenPath = CGPath(roundedRect: CGRect(x: screenX, y: screenY,
                                               width: screenW, height: screenH),
                           cornerWidth: screenCorner, cornerHeight: screenCorner,
                           transform: nil)
  ctx.addPath(screenPath)
  if fill { ctx.fillPath() } else { ctx.strokePath() }

  // --- Hinge strip (thin filled rect connecting screen to base) ---
  let hingeW = screenW * 0.6
  let hingeH = s * 0.018
  let hingeY = screenY - hingeH
  let hingePath = CGRect(x: cx - hingeW / 2, y: hingeY, width: hingeW, height: hingeH)
  ctx.fill([hingePath])

  // --- Base / keyboard deck (trapezoid — wider at front, narrower at hinge) ---
  let baseTopW = screenW + s * 0.04  // slightly wider than screen at hinge
  let baseBotW = screenW + s * 0.14  // much wider at front edge
  let baseH = s * 0.07
  let baseTopY = hingeY - s * 0.005
  let baseBotY = baseTopY - baseH

  let basePath = CGMutablePath()
  let baseTopL = cx - baseTopW / 2
  let baseTopR = cx + baseTopW / 2
  let baseBotL = cx - baseBotW / 2
  let baseBotR = cx + baseBotW / 2
  let baseCorner = s * 0.012

  // Draw with small rounded front corners
  basePath.move(to: CGPoint(x: baseTopL, y: baseTopY))
  basePath.addLine(to: CGPoint(x: baseTopR, y: baseTopY))
  basePath.addLine(to: CGPoint(x: baseBotR - baseCorner, y: baseBotY + baseCorner))
  basePath.addQuadCurve(to: CGPoint(x: baseBotR, y: baseBotY),
                        control: CGPoint(x: baseBotR, y: baseBotY + baseCorner))
  // front edge (not needed — just go straight)
  basePath.addLine(to: CGPoint(x: baseBotL, y: baseBotY))
  basePath.addQuadCurve(to: CGPoint(x: baseBotL + baseCorner, y: baseBotY + baseCorner),
                        control: CGPoint(x: baseBotL, y: baseBotY + baseCorner))
  basePath.closeSubpath()

  ctx.addPath(basePath)
  ctx.fillPath()

  // --- Front edge line (lip of the laptop) ---
  ctx.setLineWidth(lineW * 0.6)
  ctx.move(to: CGPoint(x: baseBotL + s * 0.04, y: baseBotY + baseH * 0.35))
  ctx.addLine(to: CGPoint(x: baseBotR - s * 0.04, y: baseBotY + baseH * 0.35))
  ctx.strokePath()
}

func drawEyeShape(ctx: CGContext, cx: CGFloat, cy: CGFloat, s: CGFloat,
                  lineW: CGFloat, open: Bool) {
  let eyeW = s * 0.34
  let eyeH = s * 0.14
  let leftX = cx - eyeW / 2
  let rightX = cx + eyeW / 2

  if open {
    // Full almond eye
    let path = CGMutablePath()
    path.move(to: CGPoint(x: leftX, y: cy))
    path.addCurve(to: CGPoint(x: rightX, y: cy),
                  control1: CGPoint(x: leftX + eyeW * 0.25, y: cy + eyeH),
                  control2: CGPoint(x: rightX - eyeW * 0.25, y: cy + eyeH))
    path.addCurve(to: CGPoint(x: leftX, y: cy),
                  control1: CGPoint(x: rightX - eyeW * 0.25, y: cy - eyeH),
                  control2: CGPoint(x: leftX + eyeW * 0.25, y: cy - eyeH))
    path.closeSubpath()

    ctx.setLineWidth(lineW)
    ctx.addPath(path)
    ctx.strokePath()

    // Iris
    let irisR = s * 0.058
    ctx.fillEllipse(in: CGRect(x: cx - irisR, y: cy - irisR,
                                width: irisR * 2, height: irisR * 2))
  } else {
    // Closed — downward curve + lashes
    let path = CGMutablePath()
    path.move(to: CGPoint(x: leftX, y: cy))
    path.addCurve(to: CGPoint(x: rightX, y: cy),
                  control1: CGPoint(x: leftX + eyeW * 0.25, y: cy - eyeH),
                  control2: CGPoint(x: rightX - eyeW * 0.25, y: cy - eyeH))

    ctx.setLineWidth(lineW)
    ctx.setLineCap(.round)
    ctx.addPath(path)
    ctx.strokePath()

    // Lashes
    let lashLen = s * 0.03
    for t: CGFloat in [0.2, 0.4, 0.6, 0.8] {
      let x = leftX + eyeW * t
      let yOff = eyeH * (1.0 - 4.0 * (t - 0.5) * (t - 0.5))
      let y = cy - yOff
      ctx.move(to: CGPoint(x: x, y: y))
      ctx.addLine(to: CGPoint(x: x, y: y - lashLen))
    }
    ctx.strokePath()
  }
}

func drawSymbol(ctx: CGContext, rect: CGRect) {
  let s = rect.width
  let cx = s * 0.5
  let color = CGColor(red: 0.91, green: 0.52, blue: 0.29, alpha: 1.0)  // #E8854A
  let lineW = s * 0.018

  ctx.saveGState()
  ctx.setStrokeColor(color)
  ctx.setFillColor(color)
  ctx.setLineWidth(lineW)
  ctx.setLineCap(.round)
  ctx.setLineJoin(.round)

  drawLaptopShape(ctx: ctx, cx: cx, s: s, lineW: lineW, fill: false)

  // Eye centered in screen area
  let eyeCY = s * 0.40 + s * 0.34 * 0.5  // screenY + screenH/2
  drawEyeShape(ctx: ctx, cx: cx, cy: eyeCY, s: s, lineW: lineW, open: true)

  // Pupil cutout
  let pupilR = s * 0.026
  ctx.setFillColor(CGColor(red: 0.14, green: 0.045, blue: 0.055, alpha: 1.0))
  ctx.fillEllipse(in: CGRect(x: cx - pupilR, y: eyeCY - pupilR,
                              width: pupilR * 2, height: pupilR * 2))

  ctx.restoreGState()
}

// MARK: - ICNS Generation

struct IconSize {
  let name: String
  let pixels: Int
}

let iconSizes: [IconSize] = [
  IconSize(name: "icon_16x16.png", pixels: 16),
  IconSize(name: "icon_16x16@2x.png", pixels: 32),
  IconSize(name: "icon_32x32.png", pixels: 32),
  IconSize(name: "icon_32x32@2x.png", pixels: 64),
  IconSize(name: "icon_128x128.png", pixels: 128),
  IconSize(name: "icon_128x128@2x.png", pixels: 256),
  IconSize(name: "icon_256x256.png", pixels: 256),
  IconSize(name: "icon_256x256@2x.png", pixels: 512),
  IconSize(name: "icon_512x512.png", pixels: 512),
  IconSize(name: "icon_512x512@2x.png", pixels: 1024),
]

func generateICNS() {
  let scriptDir = URL(fileURLWithPath: #file).deletingLastPathComponent()
  let projectDir = scriptDir.deletingLastPathComponent()
  let resourcesDir = projectDir.appendingPathComponent("Resources")
  let iconsetDir = FileManager.default.temporaryDirectory.appendingPathComponent("LidGuard.iconset")

  // Clean up and create iconset directory
  try? FileManager.default.removeItem(at: iconsetDir)
  try! FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)
  try? FileManager.default.createDirectory(at: resourcesDir, withIntermediateDirectories: true)

  // Generate each size
  for iconSize in iconSizes {
    let size = CGFloat(iconSize.pixels)
    let image = drawIcon(size: size)

    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
      print("Failed to generate \(iconSize.name)")
      continue
    }

    let filePath = iconsetDir.appendingPathComponent(iconSize.name)
    try! pngData.write(to: filePath)
    print("Generated \(iconSize.name) (\(iconSize.pixels)x\(iconSize.pixels))")
  }

  // Convert to .icns using iconutil
  let outputPath = resourcesDir.appendingPathComponent("AppIcon.icns")
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
  process.arguments = ["-c", "icns", "-o", outputPath.path, iconsetDir.path]

  do {
    try process.run()
    process.waitUntilExit()
    if process.terminationStatus == 0 {
      print("Created \(outputPath.path)")
    } else {
      print("iconutil failed with status \(process.terminationStatus)")
    }
  } catch {
    print("Failed to run iconutil: \(error)")
  }

  // Generate 1024x1024 PNG for App Store Connect (no alpha)
  let appStoreIcon = drawIcon(size: 1024)
  let opaqueRep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
    bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false,
    isPlanar: false, colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: opaqueRep)
  appStoreIcon.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024))
  NSGraphicsContext.restoreGraphicsState()
  if let pngData = opaqueRep.representation(using: .png, properties: [:]) {
    let appStoreIconPath = resourcesDir.appendingPathComponent("AppStoreIcon.png")
    try! pngData.write(to: appStoreIconPath)
    print("Generated AppStoreIcon.png (1024x1024, no alpha) for App Store Connect")

    // Also generate AppIcon.png (with alpha) for README
    let readmeIcon = drawIcon(size: 256)
    if let tiffData = readmeIcon.tiffRepresentation,
       let rep = NSBitmapImageRep(data: tiffData),
       let readmePng = rep.representation(using: .png, properties: [:]) {
      let readmeIconPath = resourcesDir.appendingPathComponent("AppIcon.png")
      try! readmePng.write(to: readmeIconPath)
      print("Generated AppIcon.png (256x256, with alpha) for README")
    }
  }

  // Cleanup
  try? FileManager.default.removeItem(at: iconsetDir)
}

// MARK: - Main

generateICNS()
