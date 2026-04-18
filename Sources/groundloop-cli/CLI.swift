import Foundation
import ArgumentParser
import GroundLoop

@main
struct GroundLoopCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "groundloop",
        abstract: "Manage and track LLM API usage.",
        subcommands: [Discover.self, Account.self, RayBan.self],
        defaultSubcommand: nil
    )
}

struct Discover: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Scan system for tokens and import them.")
    
    @Argument(help: "Limit discovery to a specific service (optional)")
    var service: String?
    
    func run() async throws {
        log("🔍 GroundLoop - Discovering tokens...")
        
        var serviceEnum: LLMService?
        if let serviceName = service {
            guard let found = LLMService.allCases.first(where: { $0.rawValue == serviceName.lowercased() }) else {
                log("❌ Unknown service: \(serviceName)")
                return
            }
            serviceEnum = found
            log("   Filtering for: \(found.displayName)")
        }
        log("")
        
        let usage = GroundLoop()
        do { try await usage.setup() } catch { log("⚠️ Setup error: \(error)") }
        
        log("Looking for stored credentials and running processes...")
        
        guard let accounts = try? await usage.discoverAndImport(service: serviceEnum), !accounts.isEmpty else {
            log("\n❌ No tokens discovered.")
            log("")
            log("Install and log in to one of these apps:")
            for service in LLMService.allCases {
                log("  • \(service.displayName)")
            }
            return
        }
        
        log("✅ Found and imported \(accounts.count) account(s)")
        log("Run 'swift run groundloop account' to see usage.")
    }
}

struct Account: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage accounts and view usage.",
        subcommands: [List.self, Add.self, Remove.self],
        defaultSubcommand: List.self
    )
}

extension Account {
    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List accounts and fetch usage (default).")
        
        @Argument(help: "Limit to a specific service (optional)")
        var service: String?
        
        func run() async throws {
            let usage = GroundLoop()
            do { try await usage.setup() } catch { log("⚠️ Setup error: \(error)") }
            
            var accounts = await usage.getAccounts()
            
            if let serviceName = service {
                guard let serviceEnum = LLMService.allCases.first(where: { $0.rawValue == serviceName.lowercased() }) else {
                    log("❌ Unknown service: \(serviceName)")
                    return
                }
                accounts = accounts.filter { $0.service == serviceEnum }
                log("   Filtering for: \(serviceEnum.displayName)")
            }
            
            if accounts.isEmpty {
                log("❌ No accounts database found.")
                log("Run 'swift run groundloop discover' first.")
                return
            }
            
            log("📋 Listing \(accounts.count) account(s)...")
            log("")
            
            for account in accounts {
                log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                log("📦 \(account.service.displayName) (\(account.label))")
                log("   Tokens: \(account.tokens.count)")
                
                log("   Fetching usage...")
                do {
                    let data = try await withThrowingTaskGroup(of: UsageData.self) { group in
                        group.addTask { try await usage.fetchUsage(account: account) }
                        group.addTask {
                            try await Task.sleep(for: .seconds(10))
                            throw CLIError.timeout
                        }
                        let result = try await group.next()!
                        group.cancelAll()
                        return result
                    }
                    
                    if let plan = data.plan?.name {
                        log("   Plan: \(plan)")
                    }
                    
                    if data.metrics.isEmpty {
                        log("   Usage: No data available")
                    } else {
                        for metric in data.metrics {
                            let bar = progressBar(percent: metric.usedPercent)
                            log("   \(metric.label): \(bar) \(String(format: "%.0f%%", metric.usedPercent))")
                        }
                    }
                } catch CLIError.timeout {
                    log("   Usage: ⏱ Timeout")
                } catch {
                    log("   Usage: ⚠️ \(shortError(error))")
                }
                log("")
            }
        }
    }
    
    struct Add: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Manually add an account.")
        
        @Argument(help: "Service name (claude, copilot, etc.)")
        var service: String
        
        @Argument(help: "Access token")
        var token: String
        
        @Argument(help: "Label for the account")
        var label: String = "Manual"
        
        func run() async throws {
            guard let serviceEnum = LLMService.allCases.first(where: { $0.rawValue == service.lowercased() }) else {
                log("❌ Unknown service: \(service)")
                log("Available services: \(LLMService.allCases.map { $0.rawValue }.joined(separator: ", "))")
                return
            }
            
            let usage = GroundLoop()
            do { try await usage.setup() } catch { log("⚠️ Setup error: \(error)") }
            
            let tokenInfo = TokenInfo(
                accessToken: token,
                refreshToken: nil,
                expiresAt: nil,
                source: .manual
            )
            
            var accountLabel = label
            if serviceEnum == .copilot && label == "Manual" {
                log("🔍 Attempting to fetch GitHub username...")
                if let username = await CopilotDiscovery.fetchUsername(token: token) {
                    accountLabel = username
                    log("✅ Use username: \(username)")
                }
            }
            
            let account = LLMAccount(
                service: serviceEnum,
                label: accountLabel,
                tokens: [tokenInfo],
                isActive: true
            )
            
            do {
                try await usage.saveAccount(account)
                log("✅ Added account for \(serviceEnum.displayName) (\(accountLabel))")
            } catch {
                log("❌ Failed to save account: \(error)")
            }
        }
    }
    
    struct Remove: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Remove an account.")
        
        @Argument(help: "Service name")
        var service: String
        
        @Argument(help: "Label of the account to remove")
        var label: String?
        
        func run() async throws {
            guard let serviceEnum = LLMService.allCases.first(where: { $0.rawValue == service.lowercased() }) else {
                log("❌ Unknown service: \(service)")
                return
            }
            
            let usage = GroundLoop()
            do { try await usage.setup() } catch { log("⚠️ Setup error: \(error)") }
            
            let accounts = await usage.getAccounts(for: serviceEnum)
            
            if accounts.isEmpty {
                log("No accounts found for \(serviceEnum.displayName).")
                return
            }
            
            var toRemove: LLMAccount?
            
            if let label {
                toRemove = accounts.first(where: { $0.label == label })
                if toRemove == nil {
                    log("❌ No account found with label '\(label)'")
                    log("Available labels: \(accounts.map { $0.label }.joined(separator: ", "))")
                    return
                }
            } else if accounts.count == 1 {
                toRemove = accounts.first
            } else {
                log("❌ Multiple accounts found for \(serviceEnum.displayName). Please specify a label:")
                for acc in accounts {
                    log("  • \(acc.label)")
                }
                return
            }
            
            if let account = toRemove {
                do {
                    try await usage.deleteAccount(id: account.id)
                    log("✅ Removed account: \(account.service.displayName) (\(account.label))")
                } catch {
                    log("❌ Failed to remove account: \(error)")
                }
            }
        }
    }
}

// MARK: - RayBan

struct RayBan: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Download videos from Meta Ray-Ban glasses.",
        subcommands: [Find.self, Download.self],
        defaultSubcommand: Find.self
    )
}

extension RayBan {
    struct Find: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Check if Ray-Ban glasses are connected.")

        func run() async throws {
            let downloader = RayBanDownloader()
            guard let device = downloader.findDevice() else {
                log("❌ Ray-Ban glasses not found.")
                log("   Connect glasses via USB and try again.")
                return
            }
            let videos = downloader.findVideos(on: device)
            log("✅ Found device: \(device.lastPathComponent)")
            log("   Videos ready to download: \(videos.count)")
        }
    }

    struct Download: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Download all videos to your Mac.")

        @Option(name: .shortAndLong, help: "Destination folder (default: ~/Movies/RayBan)")
        var output: String = "~/Movies/RayBan"

        func run() async throws {
            let destination = URL(fileURLWithPath: (output as NSString).expandingTildeInPath)
            log("📥 Downloading Ray-Ban videos to \(destination.path)...")
            log("")

            let downloader = RayBanDownloader()
            do {
                let result = try await downloader.download(to: destination) { msg in
                    log(msg)
                }
                log("")
                log("✅ Done: \(result.copied) downloaded, \(result.skipped) already existed")
                log("   Saved to: \(result.destination.path)")
            } catch RayBanError.deviceNotFound {
                log("❌ Device not found. Connect glasses via USB and try again.")
            } catch RayBanError.noVideosFound {
                log("⚠️ No videos found on the device.")
            } catch {
                log("❌ \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Helpers

func log(_ message: String) {
    print(message)
    fflush(stdout)
}

// ANSI Colors
let red = "\u{001B}[31m"
let green = "\u{001B}[32m"
let yellow = "\u{001B}[33m"
let reset = "\u{001B}[0m"

func progressBar(percent: Double, width: Int = 20) -> String {
    let filled = Int((percent / 100) * Double(width))
    let empty = width - filled
    
    // Determine color
    let color: String
    if percent >= 90 {
        color = red
    } else if percent >= 75 {
        color = yellow
    } else {
        color = green
    }
    
    let bar = "[" + String(repeating: "█", count: filled) + String(repeating: "░", count: empty) + "]"
    return "\(color)\(bar)\(reset)"
}

func shortError(_ error: Error) -> String {
    let str = String(describing: error)
    if str.count > 60 { return String(str.prefix(60)) + "..." }
    return str
}

enum CLIError: Error {
    case timeout
}
