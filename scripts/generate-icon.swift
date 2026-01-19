#!/usr/bin/env swift

import Cocoa
import Foundation

/// Generates the DockerBar app icon - a Docker whale with containers in a rounded box frame
class IconGenerator {

    // Icon sizes required for .icns file
    static let sizes: [(Int, String)] = [
        (16, "icon_16x16"),
        (32, "icon_16x16@2x"),
        (32, "icon_32x32"),
        (64, "icon_32x32@2x"),
        (128, "icon_128x128"),
        (256, "icon_128x128@2x"),
        (256, "icon_256x256"),
        (512, "icon_256x256@2x"),
        (512, "icon_512x512"),
        (1024, "icon_512x512@2x")
    ]

    /// Main color palette
    struct Colors {
        // Docker blue gradient
        static let dockerBlueLight = NSColor(red: 0.13, green: 0.59, blue: 0.95, alpha: 1.0)
        static let dockerBlueDark = NSColor(red: 0.08, green: 0.40, blue: 0.75, alpha: 1.0)

        // Container colors (cargo colors)
        static let containerOrange = NSColor(red: 0.95, green: 0.55, blue: 0.20, alpha: 1.0)
        static let containerRed = NSColor(red: 0.90, green: 0.30, blue: 0.25, alpha: 1.0)
        static let containerGreen = NSColor(red: 0.30, green: 0.75, blue: 0.45, alpha: 1.0)
        static let containerYellow = NSColor(red: 0.98, green: 0.80, blue: 0.25, alpha: 1.0)
        static let containerBlue = NSColor(red: 0.35, green: 0.55, blue: 0.85, alpha: 1.0)

        // Background
        static let backgroundLight = NSColor(red: 0.97, green: 0.97, blue: 0.98, alpha: 1.0)
        static let backgroundDark = NSColor(red: 0.15, green: 0.20, blue: 0.30, alpha: 1.0)

        // Frame
        static let frameColor = NSColor(red: 0.20, green: 0.25, blue: 0.35, alpha: 1.0)
    }

    /// Generate icon at specified size
    static func generateIcon(size: Int) -> NSImage {
        let cgSize = CGSize(width: size, height: size)

        let image = NSImage(size: cgSize, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else {
                return false
            }

            let scale = CGFloat(size) / 512.0

            // Draw background with rounded corners
            drawBackground(context: context, rect: rect, scale: scale)

            // Draw the whale
            drawWhale(context: context, rect: rect, scale: scale)

            // Draw containers on whale's back
            drawContainers(context: context, rect: rect, scale: scale)

            // Draw outer frame/border
            drawFrame(context: context, rect: rect, scale: scale)

            return true
        }

        return image
    }

    /// Draw rounded rectangle background with gradient
    static func drawBackground(context: CGContext, rect: CGRect, scale: CGFloat) {
        let cornerRadius = 90 * scale
        let inset: CGFloat = 8 * scale
        let bgRect = rect.insetBy(dx: inset, dy: inset)

        // Create rounded rect path
        let path = CGPath(roundedRect: bgRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

        // Fill with gradient
        context.saveGState()
        context.addPath(path)
        context.clip()

        let colors = [
            NSColor(red: 0.12, green: 0.16, blue: 0.24, alpha: 1.0).cgColor,
            NSColor(red: 0.08, green: 0.12, blue: 0.20, alpha: 1.0).cgColor
        ]
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!

        context.drawLinearGradient(gradient, start: CGPoint(x: rect.midX, y: rect.maxY), end: CGPoint(x: rect.midX, y: rect.minY), options: [])

        context.restoreGState()
    }

    /// Draw the Docker whale body
    static func drawWhale(context: CGContext, rect: CGRect, scale: CGFloat) {
        let centerX = rect.midX
        let centerY = rect.midY - 30 * scale

        // Whale body (ellipse)
        let bodyWidth: CGFloat = 280 * scale
        let bodyHeight: CGFloat = 140 * scale
        let bodyRect = CGRect(
            x: centerX - bodyWidth / 2,
            y: centerY - bodyHeight / 2,
            width: bodyWidth,
            height: bodyHeight
        )

        // Create whale body path with tail
        let whalePath = CGMutablePath()

        // Main body ellipse points
        let bodyLeft = centerX - bodyWidth / 2
        let bodyRight = centerX + bodyWidth / 2
        let bodyTop = centerY + bodyHeight / 2
        let bodyBottom = centerY - bodyHeight / 2

        // Start from left side, draw body with tail
        whalePath.move(to: CGPoint(x: bodyLeft - 40 * scale, y: centerY + 20 * scale))

        // Tail (curves up)
        whalePath.addQuadCurve(
            to: CGPoint(x: bodyLeft - 60 * scale, y: centerY + 70 * scale),
            control: CGPoint(x: bodyLeft - 70 * scale, y: centerY + 30 * scale)
        )
        whalePath.addQuadCurve(
            to: CGPoint(x: bodyLeft, y: centerY + 30 * scale),
            control: CGPoint(x: bodyLeft - 30 * scale, y: centerY + 70 * scale)
        )

        // Top of body (flat for containers)
        whalePath.addLine(to: CGPoint(x: bodyRight - 30 * scale, y: centerY + 30 * scale))

        // Head (rounded front)
        whalePath.addQuadCurve(
            to: CGPoint(x: bodyRight + 20 * scale, y: centerY - 10 * scale),
            control: CGPoint(x: bodyRight + 30 * scale, y: centerY + 30 * scale)
        )

        // Bottom of head
        whalePath.addQuadCurve(
            to: CGPoint(x: bodyRight - 50 * scale, y: bodyBottom),
            control: CGPoint(x: bodyRight + 10 * scale, y: bodyBottom + 20 * scale)
        )

        // Bottom of body
        whalePath.addLine(to: CGPoint(x: bodyLeft + 30 * scale, y: bodyBottom))

        // Connect back to tail
        whalePath.addQuadCurve(
            to: CGPoint(x: bodyLeft - 40 * scale, y: centerY + 20 * scale),
            control: CGPoint(x: bodyLeft - 20 * scale, y: bodyBottom + 20 * scale)
        )

        whalePath.closeSubpath()

        // Draw whale with gradient
        context.saveGState()
        context.addPath(whalePath)
        context.clip()

        let whaleColors = [
            Colors.dockerBlueLight.cgColor,
            Colors.dockerBlueDark.cgColor
        ]
        let whaleGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: whaleColors as CFArray, locations: [0, 1])!

        context.drawLinearGradient(whaleGradient, start: CGPoint(x: centerX, y: bodyTop + 50 * scale), end: CGPoint(x: centerX, y: bodyBottom), options: [])

        context.restoreGState()

        // Draw whale outline
        context.setStrokeColor(NSColor(white: 1, alpha: 0.3).cgColor)
        context.setLineWidth(2 * scale)
        context.addPath(whalePath)
        context.strokePath()

        // Draw eye
        let eyeSize: CGFloat = 12 * scale
        let eyeX = bodyRight - 10 * scale
        let eyeY = centerY + 5 * scale
        let eyeRect = CGRect(x: eyeX - eyeSize/2, y: eyeY - eyeSize/2, width: eyeSize, height: eyeSize)

        context.setFillColor(NSColor.white.cgColor)
        context.fillEllipse(in: eyeRect)

        let pupilSize: CGFloat = 6 * scale
        let pupilRect = CGRect(x: eyeX - pupilSize/2 + 2*scale, y: eyeY - pupilSize/2, width: pupilSize, height: pupilSize)
        context.setFillColor(NSColor(red: 0.1, green: 0.1, blue: 0.2, alpha: 1.0).cgColor)
        context.fillEllipse(in: pupilRect)

        // Water spout
        let spoutX = bodyRight - 80 * scale
        let spoutY = centerY + 40 * scale

        context.setStrokeColor(NSColor(red: 0.6, green: 0.85, blue: 1.0, alpha: 0.8).cgColor)
        context.setLineWidth(3 * scale)
        context.setLineCap(.round)

        // Spout stream
        let spoutPath = CGMutablePath()
        spoutPath.move(to: CGPoint(x: spoutX, y: spoutY))
        spoutPath.addQuadCurve(
            to: CGPoint(x: spoutX - 15 * scale, y: spoutY + 60 * scale),
            control: CGPoint(x: spoutX + 20 * scale, y: spoutY + 40 * scale)
        )
        context.addPath(spoutPath)
        context.strokePath()

        // Water droplets
        let dropletSize: CGFloat = 8 * scale
        context.setFillColor(NSColor(red: 0.6, green: 0.85, blue: 1.0, alpha: 0.8).cgColor)
        context.fillEllipse(in: CGRect(x: spoutX - 25 * scale, y: spoutY + 65 * scale, width: dropletSize, height: dropletSize))
        context.fillEllipse(in: CGRect(x: spoutX + 5 * scale, y: spoutY + 55 * scale, width: dropletSize * 0.7, height: dropletSize * 0.7))
    }

    /// Draw shipping containers on whale's back
    static func drawContainers(context: CGContext, rect: CGRect, scale: CGFloat) {
        let centerX = rect.midX
        let centerY = rect.midY - 30 * scale
        let containerTop = centerY + 35 * scale

        let containerWidth: CGFloat = 55 * scale
        let containerHeight: CGFloat = 45 * scale
        let containerSpacing: CGFloat = 8 * scale

        let containerColors = [
            Colors.containerOrange,
            Colors.containerGreen,
            Colors.containerBlue,
            Colors.containerYellow,
            Colors.containerRed
        ]

        // Bottom row - 5 containers
        let bottomRowY = containerTop
        let bottomRowStartX = centerX - (2.5 * containerWidth + 2 * containerSpacing)

        for i in 0..<5 {
            let x = bottomRowStartX + CGFloat(i) * (containerWidth + containerSpacing)
            drawContainer(
                context: context,
                rect: CGRect(x: x, y: bottomRowY, width: containerWidth, height: containerHeight),
                color: containerColors[i],
                scale: scale
            )
        }

        // Top row - 3 containers (stacked)
        let topRowY = containerTop + containerHeight + containerSpacing
        let topRowStartX = centerX - (1.5 * containerWidth + containerSpacing)

        for i in 0..<3 {
            let x = topRowStartX + CGFloat(i) * (containerWidth + containerSpacing)
            drawContainer(
                context: context,
                rect: CGRect(x: x, y: topRowY, width: containerWidth, height: containerHeight),
                color: containerColors[(i + 2) % containerColors.count],
                scale: scale
            )
        }
    }

    /// Draw a single container
    static func drawContainer(context: CGContext, rect: CGRect, color: NSColor, scale: CGFloat) {
        let cornerRadius: CGFloat = 4 * scale

        // Container body
        let path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

        // Fill with color
        context.saveGState()
        context.addPath(path)
        context.clip()

        // Gradient for 3D effect
        let lighterColor = color.blended(withFraction: 0.3, of: .white) ?? color
        let darkerColor = color.blended(withFraction: 0.3, of: .black) ?? color

        let colors = [lighterColor.cgColor, color.cgColor, darkerColor.cgColor]
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 0.5, 1])!

        context.drawLinearGradient(gradient, start: CGPoint(x: rect.midX, y: rect.maxY), end: CGPoint(x: rect.midX, y: rect.minY), options: [])

        context.restoreGState()

        // Container ridges (vertical lines)
        context.setStrokeColor(NSColor(white: 0, alpha: 0.2).cgColor)
        context.setLineWidth(1 * scale)

        let ridgeCount = 3
        let ridgeSpacing = rect.width / CGFloat(ridgeCount + 1)
        for i in 1...ridgeCount {
            let x = rect.minX + ridgeSpacing * CGFloat(i)
            context.move(to: CGPoint(x: x, y: rect.minY + 4 * scale))
            context.addLine(to: CGPoint(x: x, y: rect.maxY - 4 * scale))
            context.strokePath()
        }

        // Highlight on top edge
        context.setStrokeColor(NSColor(white: 1, alpha: 0.4).cgColor)
        context.setLineWidth(1.5 * scale)
        context.move(to: CGPoint(x: rect.minX + cornerRadius, y: rect.maxY - 1 * scale))
        context.addLine(to: CGPoint(x: rect.maxX - cornerRadius, y: rect.maxY - 1 * scale))
        context.strokePath()

        // Border
        context.setStrokeColor(NSColor(white: 0, alpha: 0.3).cgColor)
        context.setLineWidth(1 * scale)
        context.addPath(path)
        context.strokePath()
    }

    /// Draw outer frame
    static func drawFrame(context: CGContext, rect: CGRect, scale: CGFloat) {
        let cornerRadius = 90 * scale
        let inset: CGFloat = 8 * scale
        let bgRect = rect.insetBy(dx: inset, dy: inset)

        let path = CGPath(roundedRect: bgRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

        // Outer glow/shadow effect
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -4 * scale), blur: 8 * scale, color: NSColor(white: 0, alpha: 0.3).cgColor)
        context.setStrokeColor(NSColor(white: 0.3, alpha: 0.5).cgColor)
        context.setLineWidth(3 * scale)
        context.addPath(path)
        context.strokePath()
        context.restoreGState()

        // Inner highlight
        let innerRect = bgRect.insetBy(dx: 2 * scale, dy: 2 * scale)
        let innerPath = CGPath(roundedRect: innerRect, cornerWidth: cornerRadius - 2 * scale, cornerHeight: cornerRadius - 2 * scale, transform: nil)
        context.setStrokeColor(NSColor(white: 1, alpha: 0.1).cgColor)
        context.setLineWidth(1 * scale)
        context.addPath(innerPath)
        context.strokePath()
    }

    /// Save image as PNG
    static func saveAsPNG(image: NSImage, to url: URL) throws {
        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "IconGenerator", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create PNG data"])
        }
        try pngData.write(to: url)
    }

    /// Generate iconset and create .icns file
    static func generateIconset(outputDir: URL) throws {
        let iconsetDir = outputDir.appendingPathComponent("AppIcon.iconset")

        // Create iconset directory
        try FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

        print("Generating icon images...")

        for (size, name) in sizes {
            let image = generateIcon(size: size)
            let pngURL = iconsetDir.appendingPathComponent("\(name).png")
            try saveAsPNG(image: image, to: pngURL)
            print("  Created: \(name).png (\(size)x\(size))")
        }

        // Convert to .icns using iconutil
        print("\nConverting to .icns format...")
        let icnsURL = outputDir.appendingPathComponent("AppIcon.icns")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        process.arguments = ["-c", "icns", "-o", icnsURL.path, iconsetDir.path]

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0 {
            print("  Created: AppIcon.icns")

            // Clean up iconset directory
            try FileManager.default.removeItem(at: iconsetDir)
            print("\nIcon generation complete!")
            print("Output: \(icnsURL.path)")
        } else {
            throw NSError(domain: "IconGenerator", code: 2, userInfo: [NSLocalizedDescriptionKey: "iconutil failed with status \(process.terminationStatus)"])
        }
    }
}

// Main execution
let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let projectRoot = scriptDir.deletingLastPathComponent()
let distributionDir = projectRoot.appendingPathComponent("Distribution")

do {
    try IconGenerator.generateIconset(outputDir: distributionDir)
} catch {
    print("Error: \(error.localizedDescription)")
    exit(1)
}
