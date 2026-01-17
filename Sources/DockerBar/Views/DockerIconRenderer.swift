import AppKit
import DockerBarCore

/// Renders the menu bar icon in various styles
///
/// Following the CodexBar pattern for template image rendering.
/// Icon adapts to light/dark menu bar automatically via template mode.
enum DockerIconRenderer {

    // MARK: - Configuration

    struct Config {
        let style: IconStyle
        let runningCount: Int
        let totalCount: Int
        let cpuPercent: Double
        let memoryPercent: Double
        let isRefreshing: Bool
        let isConnected: Bool
        let hasError: Bool

        static var empty: Config {
            Config(
                style: .containerCount,
                runningCount: 0,
                totalCount: 0,
                cpuPercent: 0,
                memoryPercent: 0,
                isRefreshing: false,
                isConnected: false,
                hasError: false
            )
        }
    }

    // MARK: - Main Render Method

    /// Renders the menu bar icon based on configuration
    /// - Parameter config: Icon configuration
    /// - Returns: Template NSImage for menu bar
    static func render(config: Config) -> NSImage {
        let size = NSSize(width: 18, height: 18)

        let image = NSImage(size: size, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else {
                return false
            }

            // Clear background
            context.clear(rect)

            // Render based on style
            switch config.style {
            case .containerCount:
                renderContainerCountIcon(context: context, config: config, rect: rect)
            case .cpuMemoryBars:
                renderCPUMemoryBarsIcon(context: context, config: config, rect: rect)
            case .healthIndicator:
                renderHealthIndicatorIcon(context: context, config: config, rect: rect)
            }

            return true
        }

        // Template mode for automatic dark/light adaptation
        image.isTemplate = true
        return image
    }

    // MARK: - Icon Style Renderers

    /// Container count style: whale icon with badge
    private static func renderContainerCountIcon(
        context: CGContext,
        config: Config,
        rect: CGRect
    ) {
        let color = NSColor.labelColor.cgColor

        if config.isRefreshing {
            // Show refresh arrow when refreshing
            renderRefreshIcon(context: context, color: color, rect: rect)
        } else if config.hasError || !config.isConnected {
            // Show warning triangle on error
            renderWarningIcon(context: context, color: color, rect: rect)
        } else {
            // Show container/shipping box icon
            renderContainerIcon(context: context, color: color, rect: rect)
        }
    }

    /// CPU/Memory bars style: two horizontal progress bars
    private static func renderCPUMemoryBarsIcon(
        context: CGContext,
        config: Config,
        rect: CGRect
    ) {
        let color = NSColor.labelColor.cgColor
        let barHeight: CGFloat = 4
        let barSpacing: CGFloat = 3
        let padding: CGFloat = 2

        let barWidth = rect.width - (padding * 2)
        let totalHeight = (barHeight * 2) + barSpacing
        let startY = (rect.height - totalHeight) / 2

        // CPU bar (top)
        let cpuBarRect = CGRect(
            x: padding,
            y: startY + barHeight + barSpacing,
            width: barWidth,
            height: barHeight
        )
        renderProgressBar(
            context: context,
            rect: cpuBarRect,
            percent: config.cpuPercent,
            color: color
        )

        // Memory bar (bottom)
        let memBarRect = CGRect(
            x: padding,
            y: startY,
            width: barWidth,
            height: barHeight
        )
        renderProgressBar(
            context: context,
            rect: memBarRect,
            percent: config.memoryPercent,
            color: color
        )
    }

    /// Health indicator style: simple dot
    private static func renderHealthIndicatorIcon(
        context: CGContext,
        config: Config,
        rect: CGRect
    ) {
        let color = NSColor.labelColor.cgColor

        // Determine dot size based on health status
        let dotSize: CGFloat
        if config.hasError || !config.isConnected {
            dotSize = 8  // Smaller dot for error
        } else if config.runningCount == 0 && config.totalCount > 0 {
            dotSize = 10 // Medium for warning
        } else {
            dotSize = 12 // Large for healthy
        }

        let center = CGPoint(x: rect.midX, y: rect.midY)
        let dotRect = CGRect(
            x: center.x - dotSize / 2,
            y: center.y - dotSize / 2,
            width: dotSize,
            height: dotSize
        )

        context.setFillColor(color)
        context.fillEllipse(in: dotRect)
    }

    // MARK: - Helper Renderers

    private static func renderContainerIcon(
        context: CGContext,
        color: CGColor,
        rect: CGRect
    ) {
        // Simple shipping box/container icon
        let padding: CGFloat = 2
        let boxRect = rect.insetBy(dx: padding, dy: padding)

        context.setStrokeColor(color)
        context.setLineWidth(1.5)

        // Main box outline
        let boxPath = CGMutablePath()
        boxPath.addRect(CGRect(
            x: boxRect.minX,
            y: boxRect.minY,
            width: boxRect.width,
            height: boxRect.height * 0.75
        ))

        // Lid
        boxPath.move(to: CGPoint(x: boxRect.minX, y: boxRect.minY + boxRect.height * 0.75))
        boxPath.addLine(to: CGPoint(x: boxRect.midX, y: boxRect.maxY))
        boxPath.addLine(to: CGPoint(x: boxRect.maxX, y: boxRect.minY + boxRect.height * 0.75))

        context.addPath(boxPath)
        context.strokePath()

        // Center line on lid
        context.move(to: CGPoint(x: boxRect.midX, y: boxRect.minY + boxRect.height * 0.75))
        context.addLine(to: CGPoint(x: boxRect.midX, y: boxRect.maxY))
        context.strokePath()
    }

    private static func renderRefreshIcon(
        context: CGContext,
        color: CGColor,
        rect: CGRect
    ) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius: CGFloat = 6

        context.setStrokeColor(color)
        context.setLineWidth(1.5)
        context.setLineCap(.round)

        // Draw circular arrow
        let startAngle = CGFloat.pi * 0.25
        let endAngle = CGFloat.pi * 1.75

        context.addArc(
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        context.strokePath()

        // Arrow head
        let arrowEnd = CGPoint(
            x: center.x + radius * cos(endAngle),
            y: center.y + radius * sin(endAngle)
        )

        let arrowPath = CGMutablePath()
        arrowPath.move(to: arrowEnd)
        arrowPath.addLine(to: CGPoint(x: arrowEnd.x + 3, y: arrowEnd.y - 2))
        arrowPath.move(to: arrowEnd)
        arrowPath.addLine(to: CGPoint(x: arrowEnd.x + 2, y: arrowEnd.y + 3))

        context.addPath(arrowPath)
        context.strokePath()
    }

    private static func renderWarningIcon(
        context: CGContext,
        color: CGColor,
        rect: CGRect
    ) {
        let padding: CGFloat = 2
        let triangleRect = rect.insetBy(dx: padding, dy: padding)

        context.setStrokeColor(color)
        context.setLineWidth(1.5)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        // Warning triangle
        let trianglePath = CGMutablePath()
        trianglePath.move(to: CGPoint(x: triangleRect.midX, y: triangleRect.maxY))
        trianglePath.addLine(to: CGPoint(x: triangleRect.minX, y: triangleRect.minY))
        trianglePath.addLine(to: CGPoint(x: triangleRect.maxX, y: triangleRect.minY))
        trianglePath.closeSubpath()

        context.addPath(trianglePath)
        context.strokePath()

        // Exclamation mark
        let exclamationTop = triangleRect.midY + 2
        let exclamationBottom = triangleRect.midY - 2
        let dotY = triangleRect.minY + 3

        context.move(to: CGPoint(x: triangleRect.midX, y: exclamationTop))
        context.addLine(to: CGPoint(x: triangleRect.midX, y: exclamationBottom))
        context.strokePath()

        // Dot
        let dotRect = CGRect(
            x: triangleRect.midX - 1,
            y: dotY - 1,
            width: 2,
            height: 2
        )
        context.fillEllipse(in: dotRect)
    }

    private static func renderProgressBar(
        context: CGContext,
        rect: CGRect,
        percent: Double,
        color: CGColor
    ) {
        let cornerRadius: CGFloat = rect.height / 2

        // Background (stroke only for template mode)
        let bgPath = CGPath(
            roundedRect: rect,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )
        context.setStrokeColor(color)
        context.setLineWidth(0.5)
        context.addPath(bgPath)
        context.strokePath()

        // Filled portion
        let fillWidth = max(0, min(1, percent / 100)) * rect.width
        if fillWidth > 0 {
            let fillRect = CGRect(
                x: rect.minX,
                y: rect.minY,
                width: fillWidth,
                height: rect.height
            )
            let fillPath = CGPath(
                roundedRect: fillRect,
                cornerWidth: cornerRadius,
                cornerHeight: cornerRadius,
                transform: nil
            )
            context.setFillColor(color)
            context.addPath(fillPath)
            context.fillPath()
        }
    }
}
