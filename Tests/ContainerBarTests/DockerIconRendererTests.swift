import Testing
import AppKit
@testable import ContainerBar
@testable import ContainerBarCore

@Suite("DockerIconRenderer Tests")
struct DockerIconRendererTests {

    @Test("Renders template image")
    func rendersTemplateImage() {
        let config = DockerIconRenderer.Config(
            style: .containerCount,
            runningCount: 5,
            totalCount: 8,
            cpuPercent: 25.0,
            memoryPercent: 50.0,
            isRefreshing: false,
            isConnected: true,
            hasError: false
        )

        let image = DockerIconRenderer.render(config: config)

        #expect(image.isTemplate == true)
        #expect(image.size.width == 18)
        #expect(image.size.height == 18)
    }

    @Test("Renders different styles without crashing")
    func rendersDifferentStyles() {
        let baseConfig = DockerIconRenderer.Config(
            style: .containerCount,
            runningCount: 3,
            totalCount: 5,
            cpuPercent: 30.0,
            memoryPercent: 60.0,
            isRefreshing: false,
            isConnected: true,
            hasError: false
        )

        // Test container count style
        let countConfig = baseConfig
        let countImage = DockerIconRenderer.render(config: countConfig)
        #expect(countImage.size.width > 0)

        // Test CPU/Memory bars style
        let barsConfig = DockerIconRenderer.Config(
            style: .cpuMemoryBars,
            runningCount: baseConfig.runningCount,
            totalCount: baseConfig.totalCount,
            cpuPercent: baseConfig.cpuPercent,
            memoryPercent: baseConfig.memoryPercent,
            isRefreshing: baseConfig.isRefreshing,
            isConnected: baseConfig.isConnected,
            hasError: baseConfig.hasError
        )
        let barsImage = DockerIconRenderer.render(config: barsConfig)
        #expect(barsImage.size.width > 0)

        // Test health indicator style
        let healthConfig = DockerIconRenderer.Config(
            style: .healthIndicator,
            runningCount: baseConfig.runningCount,
            totalCount: baseConfig.totalCount,
            cpuPercent: baseConfig.cpuPercent,
            memoryPercent: baseConfig.memoryPercent,
            isRefreshing: baseConfig.isRefreshing,
            isConnected: baseConfig.isConnected,
            hasError: baseConfig.hasError
        )
        let healthImage = DockerIconRenderer.render(config: healthConfig)
        #expect(healthImage.size.width > 0)
    }

    @Test("Renders refresh state")
    func rendersRefreshState() {
        let config = DockerIconRenderer.Config(
            style: .containerCount,
            runningCount: 0,
            totalCount: 0,
            cpuPercent: 0,
            memoryPercent: 0,
            isRefreshing: true,
            isConnected: true,
            hasError: false
        )

        let image = DockerIconRenderer.render(config: config)
        #expect(image.isTemplate == true)
    }

    @Test("Renders error state")
    func rendersErrorState() {
        let config = DockerIconRenderer.Config(
            style: .containerCount,
            runningCount: 0,
            totalCount: 0,
            cpuPercent: 0,
            memoryPercent: 0,
            isRefreshing: false,
            isConnected: false,
            hasError: true
        )

        let image = DockerIconRenderer.render(config: config)
        #expect(image.isTemplate == true)
    }

    @Test("Empty config produces valid image")
    func emptyConfigProducesImage() {
        let config = DockerIconRenderer.Config.empty

        let image = DockerIconRenderer.render(config: config)
        #expect(image.size.width == 18)
        #expect(image.size.height == 18)
    }
}
