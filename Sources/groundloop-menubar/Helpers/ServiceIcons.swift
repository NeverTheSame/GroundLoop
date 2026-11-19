import SwiftUI
import GroundLoop

/// Returns the SVG file name (without extension) for a service, if one exists.
func serviceLogoName(for service: LLMService) -> String? {
    switch service {
    case .claude: "claude"
    case .copilot: "githubcopilot"
    case .codex: "openai"
    case .cursor: "cursor"
    case .windsurf: "windsurf"
    case .antigravity: "google-antigravity"
    case .glm: "glm"
    case .openrouter: nil
    }
}

/// SF Symbol fallback for services without a custom SVG logo.
func serviceIcon(for service: LLMService) -> String {
    switch service {
    case .claude: "brain.head.profile"
    case .copilot: "airplane"
    case .cursor: "cursorarrow.rays"
    case .windsurf: "wind"
    case .antigravity: "arrow.up.circle"
    case .codex: "book.closed"
    case .glm: "sparkles"
    case .openrouter: "arrow.triangle.branch"
    }
}

func serviceColor(for service: LLMService) -> Color {
    switch service {
    case .claude: .orange
    case .copilot: .blue
    case .cursor: .purple
    case .windsurf: .green
    case .antigravity: .indigo
    case .codex: .purple
    case .glm: .cyan
    case .openrouter: .pink
    }
}

/// SwiftPM resource bundle produced for the menubar executable.
private let menubarResourceBundleName = "GroundLoop_groundloop-menubar"

/// URL of a service SVG, or nil if the packaged resource bundle cannot be found.
func serviceLogoURL(_ name: String) -> URL? {
    PackageResourceBundle.url(
        named: menubarResourceBundleName,
        forResource: name,
        withExtension: "svg",
        subdirectory: "ServiceLogos"
    )
}

/// Loads an SVG from the bundle's ServiceLogos directory as a template NSImage.
private func loadServiceLogo(_ name: String) -> NSImage? {
    guard let url = serviceLogoURL(name) else { return nil }
    guard let image = NSImage(contentsOf: url) else { return nil }
    image.isTemplate = true
    return image
}

/// Displays either a custom SVG logo or an SF Symbol for a service, tinted with the service color.
struct ServiceIconView: View {
    let service: LLMService

    var body: some View {
        if let logoName = serviceLogoName(for: service),
           let nsImage = loadServiceLogo(logoName) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 16, height: 16)
                .foregroundColor(serviceColor(for: service))
        } else {
            Image(systemName: serviceIcon(for: service))
                .foregroundColor(serviceColor(for: service))
        }
    }
}
