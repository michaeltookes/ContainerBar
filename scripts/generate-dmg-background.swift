#!/usr/bin/env swift

import Cocoa
import Foundation

/// Generates the DMG background image with arrow pointing to Applications
class DMGBackgroundGenerator {

    static let width: CGFloat = 660
    static let height: CGFloat = 400

    static func generate() -> NSImage {
        let size = NSSize(width: width, height: height)

        let image = NSImage(size: size, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else {
                return false
            }

            // Draw background gradient (light gray like macOS Finder)
            let bgColors = [
                NSColor(red: 0.95, green: 0.95, blue: 0.96, alpha: 1.0).cgColor,
                NSColor(red: 0.90, green: 0.90, blue: 0.92, alpha: 1.0).cgColor
            ]
            let bgGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: bgColors as CFArray, locations: [0, 1])!
            context.drawLinearGradient(bgGradient, start: CGPoint(x: 0, y: rect.maxY), end: CGPoint(x: 0, y: 0), options: [])

            // Draw subtle border
            context.setStrokeColor(NSColor(white: 0.8, alpha: 1.0).cgColor)
            context.setLineWidth(1)
            context.stroke(rect.insetBy(dx: 0.5, dy: 0.5))

            // Draw arrow in the center
            drawArrow(context: context, rect: rect)

            // Draw "Drag to install" text (optional, subtle)
            drawInstructions(context: context, rect: rect)

            return true
        }

        return image
    }

    static func drawArrow(context: CGContext, rect: CGRect) {
        let centerY = rect.midY + 20 // Slightly above center to account for icon labels
        let arrowX = rect.midX
        let arrowLength: CGFloat = 50
        let arrowHeadSize: CGFloat = 15

        context.saveGState()

        // Arrow color (dark gray)
        context.setStrokeColor(NSColor(white: 0.3, alpha: 0.8).cgColor)
        context.setFillColor(NSColor(white: 0.3, alpha: 0.8).cgColor)
        context.setLineWidth(3)
        context.setLineCap(.round)

        // Arrow shaft
        let shaftStart = CGPoint(x: arrowX - arrowLength/2, y: centerY)
        let shaftEnd = CGPoint(x: arrowX + arrowLength/2 - arrowHeadSize/2, y: centerY)

        context.move(to: shaftStart)
        context.addLine(to: shaftEnd)
        context.strokePath()

        // Arrow head
        let headTip = CGPoint(x: arrowX + arrowLength/2, y: centerY)
        let headTop = CGPoint(x: arrowX + arrowLength/2 - arrowHeadSize, y: centerY + arrowHeadSize/2)
        let headBottom = CGPoint(x: arrowX + arrowLength/2 - arrowHeadSize, y: centerY - arrowHeadSize/2)

        let arrowPath = CGMutablePath()
        arrowPath.move(to: headTip)
        arrowPath.addLine(to: headTop)
        arrowPath.addLine(to: headBottom)
        arrowPath.closeSubpath()

        context.addPath(arrowPath)
        context.fillPath()

        context.restoreGState()
    }

    static func drawInstructions(context: CGContext, rect: CGRect) {
        // Optional: Draw subtle instruction text at the bottom
        // This is often omitted in modern DMGs as the layout is self-explanatory
    }

    static func saveAsPNG(image: NSImage, to url: URL) throws {
        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "DMGBackgroundGenerator", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create PNG data"])
        }
        try pngData.write(to: url)
    }
}

// Main execution
let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let projectRoot = scriptDir.deletingLastPathComponent()
let distributionDir = projectRoot.appendingPathComponent("Distribution")

do {
    let image = DMGBackgroundGenerator.generate()
    let outputURL = distributionDir.appendingPathComponent("dmg-background.png")
    try DMGBackgroundGenerator.saveAsPNG(image: image, to: outputURL)
    print("DMG background created: \(outputURL.path)")
} catch {
    print("Error: \(error.localizedDescription)")
    exit(1)
}
