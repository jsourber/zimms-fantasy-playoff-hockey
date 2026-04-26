import Foundation

@MainActor
final class StandingsService: ObservableObject {

    // MARK: - macOS-only: shell out to scorer.py
    #if os(macOS)
    /// Absolute path to scorer.py. Override in the app's Settings panel if needed.
    @Published var scorerPath: String = UserDefaults.standard.string(forKey: "scorerPath")
        ?? "/Users/jacobsourber/Desktop/claude-workspace/fantasy-hockey/scorer.py" {
        didSet { UserDefaults.standard.set(scorerPath, forKey: "scorerPath") }
    }

    @Published var pythonPath: String = UserDefaults.standard.string(forKey: "pythonPath") ?? "/usr/bin/python3" {
        didSet { UserDefaults.standard.set(pythonPath, forKey: "pythonPath") }
    }
    #else
    /// iOS: URL of the hosted standings.json. Defaults to the league's GitHub-hosted feed.
    static let defaultStandingsUrl = "https://raw.githubusercontent.com/jsourber/zimms-fantasy-playoff-hockey/main/public/standings.json"

    @Published var standingsUrl: String = UserDefaults.standard.string(forKey: "standingsUrl") ?? StandingsService.defaultStandingsUrl {
        didSet { UserDefaults.standard.set(standingsUrl, forKey: "standingsUrl") }
    }
    #endif

    @Published var data: StandingsResponse?
    @Published var isLoading: Bool = false
    @Published var lastError: String?
    @Published var lastRefreshedAt: Date?

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let json = try await fetchJSON()
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            decoder.dateDecodingStrategy = .iso8601
            data = try decoder.decode(StandingsResponse.self, from: json)
            lastError = nil
            lastRefreshedAt = Date()
        } catch let e as DecodingError {
            lastError = "Decode error: \(e)"
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func fetchJSON() async throws -> Data {
        #if os(macOS)
        return try await runScorer()
        #else
        return try await fetchFromURL()
        #endif
    }

    #if os(macOS)
    private func runScorer() async throws -> Data {
        let py = pythonPath
        let scorer = scorerPath
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: py)
                proc.arguments = [scorer, "score", "--json"]
                let stdout = Pipe()
                let stderr = Pipe()
                proc.standardOutput = stdout
                proc.standardError = stderr

                do {
                    try proc.run()
                } catch {
                    cont.resume(throwing: error)
                    return
                }
                proc.waitUntilExit()

                let outData = stdout.fileHandleForReading.readDataToEndOfFile()
                let errData = stderr.fileHandleForReading.readDataToEndOfFile()

                if proc.terminationStatus != 0 {
                    let msg = String(data: errData, encoding: .utf8) ?? "scorer.py exited \(proc.terminationStatus)"
                    cont.resume(throwing: NSError(
                        domain: "PlayoffPool",
                        code: Int(proc.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey: msg]
                    ))
                    return
                }
                cont.resume(returning: outData)
            }
        }
    }
    #else
    private func fetchFromURL() async throws -> Data {
        let urlString = standingsUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlString.isEmpty else {
            throw NSError(
                domain: "PlayoffPool",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Set the standings.json URL in Settings."]
            )
        }
        // Append a cache-buster so the GitHub raw CDN (max-age=300) and any
        // intermediate caches don't return a stale snapshot.
        let bust = Int(Date().timeIntervalSince1970)
        let separator = urlString.contains("?") ? "&" : "?"
        guard let url = URL(string: "\(urlString)\(separator)t=\(bust)") else {
            throw NSError(
                domain: "PlayoffPool",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid standings URL."]
            )
        }
        var req = URLRequest(url: url)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            throw NSError(
                domain: "PlayoffPool",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode) from standings URL."]
            )
        }
        return data
    }
    #endif
}
