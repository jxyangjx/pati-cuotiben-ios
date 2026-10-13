import Foundation

enum InferenceMode: String {
    case stub
    case live
}

enum InferenceConfig {
    static let fallbackBaseURL = "http://127.0.0.1:8787"

    static func sanitized(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("$(") { return "" }
        return trimmed
    }

    static func bundledValue(_ key: String, bundle: Bundle) -> String {
        sanitized(bundle.object(forInfoDictionaryKey: key) as? String ?? "")
    }

    static func baseURLString(userValue: String, bundle: Bundle = .main) -> String {
        let typed = sanitized(userValue)
        if !typed.isEmpty { return typed }
        let bundled = bundledValue("InferenceBaseURL", bundle: bundle)
        return bundled.isEmpty ? fallbackBaseURL : bundled
    }

    static func gatewayURL(userValue: String, bundle: Bundle = .main) -> URL? {
        let candidate = baseURLString(userValue: userValue, bundle: bundle)
        guard let url = URL(string: candidate) else { return nil }
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        guard let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    static func endpoint(_ base: URL, path: String) -> URL? {
        var root = base.absoluteString
        while root.hasSuffix("/") {
            root.removeLast()
        }
        return URL(string: root + path)
    }

    /// Keychain wins. A build-time value is used only when the Keychain entry is empty.
    static func apiKey(bundle: Bundle = .main) -> String {
        let stored = load().trimmingCharacters(in: .whitespacesAndNewlines)
        if !stored.isEmpty { return stored }
        return bundledValue("InferenceAPIKey", bundle: bundle)
    }

    private static func load() -> String {
        InferenceKeychain.load()
    }
}

enum InferenceClientFactory {
    struct Resolved {
        var mode: InferenceMode
        var client: any InferenceClient
    }

    static func make(defaults: UserDefaults = .standard, bundle: Bundle = .main) -> Resolved {
        let raw = defaults.string(forKey: DefaultsKey.inferenceMode) ?? InferenceMode.stub.rawValue
        guard raw == InferenceMode.live.rawValue else {
            return Resolved(mode: .stub, client: StubInferenceClient())
        }
        let userURL = defaults.string(forKey: DefaultsKey.inferenceBaseURL) ?? ""
        guard let url = InferenceConfig.gatewayURL(userValue: userURL, bundle: bundle) else {
            return Resolved(mode: .live, client: UnavailableInferenceClient())
        }
        return Resolved(
            mode: .live,
            client: HTTPInferenceClient(baseURL: url, apiKey: InferenceConfig.apiKey(bundle: bundle))
        )
    }
}
