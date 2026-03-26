Vendored compatibility copy of WhisperKit used by Voxt.

Source:
- upstream: `https://github.com/yazins-ai/WhisperKit`
- branch: `fix/swift-transformers-compat`

Local changes:
- trimmed to the `ArgmaxCore` and `WhisperKit` targets only
- `Package.swift` simplified for Voxt
- `Foundation.pow` fix in `Sources/ArgmaxCore/FoundationExtensions.swift`
