import Foundation

struct RemoteModelOption: Hashable, Identifiable {
    let id: String
    let title: String
}

enum RemoteASRProvider: String, CaseIterable, Identifiable {
    case openAIWhisper
    case doubaoASR
    case glmASR
    case aliyunBailianASR

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openAIWhisper:
            return AppLocalization.localizedString("OpenAI Whisper")
        case .doubaoASR:
            return AppLocalization.localizedString("Doubao ASR")
        case .glmASR:
            return AppLocalization.localizedString("GLM ASR")
        case .aliyunBailianASR:
            return AppLocalization.localizedString("Aliyun Bailian ASR")
        }
    }

    var suggestedModel: String {
        switch self {
        case .openAIWhisper:
            return "whisper-1"
        case .doubaoASR:
            return DoubaoASRConfiguration.modelV2
        case .glmASR:
            return "glm-asr-1"
        case .aliyunBailianASR:
            return "fun-asr-realtime"
        }
    }

    var modelOptions: [RemoteModelOption] {
        switch self {
        case .openAIWhisper:
            return [
                RemoteModelOption(id: "whisper-1", title: "Whisper-1"),
                RemoteModelOption(id: "gpt-4o-mini-transcribe", title: "GPT-4o Mini Transcribe"),
                RemoteModelOption(id: "gpt-4o-transcribe", title: "GPT-4o Transcribe")
            ]
        case .doubaoASR:
            return [
                RemoteModelOption(id: DoubaoASRConfiguration.modelV2, title: "Doubao ASR 2.0 (Hourly)"),
                RemoteModelOption(id: DoubaoASRConfiguration.modelV1, title: "Doubao ASR 1.0 (Hourly)")
            ]
        case .glmASR:
            return [
                RemoteModelOption(id: "glm-asr-2512", title: "GLM-ASR-2512"),
                RemoteModelOption(id: "glm-asr-1", title: "GLM-ASR-1")
            ]
        case .aliyunBailianASR:
            return [
                RemoteModelOption(id: "qwen3-asr-flash-realtime", title: "Qwen3 ASR Flash Realtime"),
                RemoteModelOption(id: "qwen3-asr-flash-realtime-2026-02-10", title: "Qwen3 ASR Flash Realtime (2026-02-10)"),
                RemoteModelOption(id: "qwen3-asr-flash-realtime-2025-10-27", title: "Qwen3 ASR Flash Realtime (2025-10-27)"),
                RemoteModelOption(id: "fun-asr-realtime", title: "Fun ASR Realtime"),
                RemoteModelOption(id: "fun-asr-realtime-2026-02-28", title: "Fun ASR Realtime (2026-02-28)"),
                RemoteModelOption(id: "fun-asr-realtime-2025-11-07", title: "Fun ASR Realtime (2025-11-07)"),
                RemoteModelOption(id: "fun-asr-realtime-2025-09-15", title: "Fun ASR Realtime (2025-09-15)"),
                RemoteModelOption(id: "fun-asr-flash-8k-realtime", title: "Fun ASR Flash 8k Realtime"),
                RemoteModelOption(id: "fun-asr-flash-8k-realtime-2026-01-28", title: "Fun ASR Flash 8k Realtime (2026-01-28)"),
                RemoteModelOption(id: "paraformer-realtime-v2", title: "Paraformer Realtime V2"),
                RemoteModelOption(id: "paraformer-realtime-v1", title: "Paraformer Realtime V1"),
                RemoteModelOption(id: "paraformer-realtime-8k-v2", title: "Paraformer Realtime 8k V2"),
                RemoteModelOption(id: "paraformer-realtime-8k-v1", title: "Paraformer Realtime 8k V1")
            ]
        }
    }
}

enum RemoteLLMProvider: String, CaseIterable, Identifiable {
    case anthropic
    case google
    case openAI
    case ollama
    case deepseek
    case openrouter
    case grok
    case zai
    case volcengine
    case kimi
    case lmStudio
    case minimax
    case aliyunBailian

    var id: String { rawValue }

    var title: String {
        switch self {
        case .anthropic:
            return AppLocalization.localizedString("Anthropic")
        case .google:
            return AppLocalization.localizedString("Google")
        case .openAI:
            return AppLocalization.localizedString("OpenAI")
        case .ollama:
            return AppLocalization.localizedString("Ollama")
        case .deepseek:
            return AppLocalization.localizedString("DeepSeek")
        case .openrouter:
            return AppLocalization.localizedString("OpenRouter")
        case .grok:
            return AppLocalization.localizedString("xAI (Grok)")
        case .zai:
            return AppLocalization.localizedString("Z.ai")
        case .volcengine:
            return AppLocalization.localizedString("Volcengine")
        case .kimi:
            return AppLocalization.localizedString("Kimi")
        case .lmStudio:
            return AppLocalization.localizedString("LM Studio")
        case .minimax:
            return AppLocalization.localizedString("MiniMax")
        case .aliyunBailian:
            return AppLocalization.localizedString("Aliyun Bailian")
        }
    }

    var suggestedModel: String {
        switch self {
        case .anthropic:
            return "claude-sonnet-4-6"
        case .google:
            return "gemini-2.5-pro"
        case .openAI:
            return "gpt-5.2"
        case .ollama:
            return "qwen2.5"
        case .deepseek:
            return "deepseek-chat"
        case .openrouter:
            return "openrouter/auto"
        case .grok:
            return "grok-4"
        case .zai:
            return "glm-5"
        case .volcengine:
            return "doubao-seed-2-0-pro-260215"
        case .kimi:
            return "kimi-k2.5"
        case .lmStudio:
            return "llama3.1"
        case .minimax:
            return "MiniMax-M2.5"
        case .aliyunBailian:
            return "qwen-plus-latest"
        }
    }

    var modelOptions: [RemoteModelOption] {
        let merged = latestModelOptions + basicModelOptions + advancedModelOptions
        var seen = Set<String>()
        return merged.filter { seen.insert($0.id).inserted }
    }

    var latestModelOptions: [RemoteModelOption] {
        switch self {
        case .anthropic:
            return [
                RemoteModelOption(id: "claude-opus-4-6", title: "Claude Opus 4.6"),
                RemoteModelOption(id: "claude-sonnet-4-6", title: "Claude Sonnet 4.6"),
                RemoteModelOption(id: "claude-opus-4-5-20251101", title: "Claude Opus 4.5"),
                RemoteModelOption(id: "claude-sonnet-4-5-20250929", title: "Claude Sonnet 4.5")
            ]
        case .google:
            return [
                RemoteModelOption(id: "gemini-3.1-pro-preview", title: "Gemini 3.1 Pro Preview"),
                RemoteModelOption(id: "gemini-3-pro-preview", title: "Gemini 3 Pro Preview"),
                RemoteModelOption(id: "gemini-2.5-pro", title: "Gemini 2.5 Pro"),
                RemoteModelOption(id: "gemini-2.5-pro-preview-06-05", title: "Gemini 2.5 Pro Preview 06-05")
            ]
        case .openAI:
            return [
                RemoteModelOption(id: "gpt-5.2", title: "GPT-5.2"),
                RemoteModelOption(id: "gpt-5.2-chat-latest", title: "GPT-5.2 Chat"),
                RemoteModelOption(id: "gpt-5.2-pro", title: "GPT-5.2 pro"),
                RemoteModelOption(id: "gpt-5.1", title: "GPT-5.1"),
                RemoteModelOption(id: "gpt-5.1-chat-latest", title: "GPT-5.1 Chat"),
                RemoteModelOption(id: "gpt-5.1-codex", title: "GPT-5.1 Codex"),
                RemoteModelOption(id: "gpt-5.1-codex-mini", title: "GPT-5.1 Codex mini"),
                RemoteModelOption(id: "gpt-5-pro", title: "GPT-5 pro"),
                RemoteModelOption(id: "gpt-5-codex", title: "GPT-5 Codex"),
                RemoteModelOption(id: "gpt-5", title: "GPT-5"),
                RemoteModelOption(id: "gpt-5-chat-latest", title: "GPT-5 Chat"),
                RemoteModelOption(id: "gpt-5-mini", title: "GPT-5 mini"),
                RemoteModelOption(id: "gpt-5-nano", title: "GPT-5 nano")
            ]
        case .ollama:
            return [
                RemoteModelOption(id: "deepseek-v3.1:671b", title: "DeepSeek V3.1"),
                RemoteModelOption(id: "gpt-oss:120b", title: "GPT-OSS 120B"),
                RemoteModelOption(id: "qwen3-coder:480b", title: "Qwen3 Coder 480B"),
                RemoteModelOption(id: "deepseek-r1", title: "DeepSeek R1")
            ]
        case .deepseek: return [RemoteModelOption(id: "deepseek-chat", title: "DeepSeek V3.2")]
        case .openrouter:
            return [
                RemoteModelOption(id: "openrouter/auto", title: "Auto (best for prompt)"),
                RemoteModelOption(id: "deepseek/deepseek-chat-v3.1", title: "DeepSeek V3.1"),
                RemoteModelOption(id: "openai/gpt-4.1", title: "GPT-4.1"),
                RemoteModelOption(id: "google/gemini-2.5-pro", title: "Gemini 2.5 Pro")
            ]
        case .grok:
            return [
                RemoteModelOption(id: "grok-4-1-fast-reasoning", title: "Grok 4.1 Fast"),
                RemoteModelOption(id: "grok-4-1-fast-non-reasoning", title: "Grok 4.1 Fast (Non-Reasoning)"),
                RemoteModelOption(id: "grok-4", title: "Grok 4 0709")
            ]
        case .zai:
            return [
                RemoteModelOption(id: "glm-5", title: "GLM-5"),
                RemoteModelOption(id: "glm-4.7", title: "GLM-4.7"),
                RemoteModelOption(id: "glm-4.6", title: "GLM-4.6"),
                RemoteModelOption(id: "glm-4.5", title: "GLM-4.5")
            ]
        case .volcengine:
            return [
                RemoteModelOption(id: "doubao-seed-2-0-pro-260215", title: "Doubao Seed 2.0 Pro (260215)"),
                RemoteModelOption(id: "doubao-seed-2-0-lite-260215", title: "Doubao Seed 2.0 Lite (260215)"),
                RemoteModelOption(id: "doubao-seed-2-0-mini-260215", title: "Doubao Seed 2.0 Mini (260215)"),
                RemoteModelOption(id: "doubao-seed-2-0-code-preview-260215", title: "Doubao Seed 2.0 Code Preview (260215)"),
                RemoteModelOption(id: "doubao-seed-1-8-251228", title: "Doubao Seed 1.8 (251228)"),
                RemoteModelOption(id: "glm-4-7-251222", title: "GLM-4.7 (251222)"),
                RemoteModelOption(id: "doubao-seed-code-preview-251028", title: "Doubao Seed Code Preview (251028)"),
                RemoteModelOption(id: "doubao-seed-1-6-lite-251015", title: "Doubao Seed 1.6 Lite (251015)"),
                RemoteModelOption(id: "doubao-seed-1-6-flash-250828", title: "Doubao Seed 1.6 Flash (250828)"),
                RemoteModelOption(id: "doubao-seed-translation-250915", title: "Doubao Seed Translation (250915)"),
                RemoteModelOption(id: "doubao-seed-1-6-vision-250815", title: "Doubao Seed 1.6 Vision (250815)")
            ]
        case .kimi:
            return [
                RemoteModelOption(id: "kimi-k2.5", title: "Kimi K2.5"),
                RemoteModelOption(id: "kimi-k2-thinking", title: "Kimi K2 Thinking"),
                RemoteModelOption(id: "kimi-latest", title: "Kimi Latest")
            ]
        case .lmStudio:
            return [
                RemoteModelOption(id: "llama3.1", title: "Llama 3.1 8B"),
                RemoteModelOption(id: "qwen2.5-14b-instruct", title: "Qwen2.5 14B")
            ]
        case .minimax:
            return [
                RemoteModelOption(id: "MiniMax-M2.5", title: "MiniMax M2.5"),
                RemoteModelOption(id: "MiniMax-M2.5-Lightning", title: "MiniMax M2.5 Lightning"),
                RemoteModelOption(id: "MiniMax-M2.1", title: "MiniMax M2.1")
            ]
        case .aliyunBailian:
            return [
                RemoteModelOption(id: "qwen-max-latest", title: "Qwen Max Latest"),
                RemoteModelOption(id: "qwen-plus-latest", title: "Qwen Plus Latest"),
                RemoteModelOption(id: "qwen-turbo-latest", title: "Qwen Turbo Latest")
            ]
        }
    }

    var basicModelOptions: [RemoteModelOption] {
        switch self {
        case .anthropic:
            return [
                RemoteModelOption(id: "claude-haiku-4-5-20251001", title: "Claude Haiku 4.5"),
                RemoteModelOption(id: "claude-3-haiku-20240307", title: "Claude 3 Haiku")
            ]
        case .google:
            return [
                RemoteModelOption(id: "gemini-2.5-flash", title: "Gemini 2.5 Flash"),
                RemoteModelOption(id: "gemini-2.5-flash-lite", title: "Gemini 2.5 Flash-Lite"),
                RemoteModelOption(id: "gemini-2.0-flash", title: "Gemini 2.0 Flash"),
                RemoteModelOption(id: "gemini-2.0-flash-001", title: "Gemini 2.0 Flash 001"),
                RemoteModelOption(id: "gemini-1.5-flash-002", title: "Gemini 1.5 Flash 002")
            ]
        case .openAI:
            return [
                RemoteModelOption(id: "gpt-4o-mini", title: "GPT-4o mini"),
                RemoteModelOption(id: "gpt-4o-mini-search-preview", title: "GPT-4o mini Search Preview"),
                RemoteModelOption(id: "gpt-4.1-nano", title: "GPT-4.1 nano"),
                RemoteModelOption(id: "gpt-3.5-turbo", title: "GPT-3.5 Turbo"),
                RemoteModelOption(id: "gpt-3.5-turbo-0125", title: "GPT-3.5 Turbo 0125"),
                RemoteModelOption(id: "gpt-3.5-turbo-1106", title: "GPT-3.5 Turbo 1106"),
                RemoteModelOption(id: "gpt-3.5-turbo-instruct", title: "GPT-3.5 Turbo Instruct")
            ]
        case .ollama:
            return [
                RemoteModelOption(id: "qwen2.5", title: "Qwen2.5 7B"),
                RemoteModelOption(id: "qwen3", title: "Qwen3 7B"),
                RemoteModelOption(id: "llama3.1", title: "Llama 3.1 8B"),
                RemoteModelOption(id: "mistral", title: "Mistral 7B"),
                RemoteModelOption(id: "gemma2", title: "Gemma 2 9B")
            ]
        case .deepseek: return [RemoteModelOption(id: "deepseek-chat", title: "DeepSeek V3.2")]
        case .openrouter:
            return [
                RemoteModelOption(id: "google/gemini-2.5-flash", title: "Gemini 2.5 Flash"),
                RemoteModelOption(id: "openai/gpt-4.1-mini", title: "GPT-4.1 mini"),
                RemoteModelOption(id: "qwen/qwen3-14b", title: "Qwen3 14B")
            ]
        case .grok:
            return [
                RemoteModelOption(id: "grok-3", title: "Grok 3"),
                RemoteModelOption(id: "grok-3-mini", title: "Grok 3 Mini")
            ]
        case .zai:
            return [
                RemoteModelOption(id: "glm-4.7-flash", title: "GLM-4.7-Flash"),
                RemoteModelOption(id: "glm-4.5-air", title: "GLM-4.5-Air"),
                RemoteModelOption(id: "glm-4.5-airx", title: "GLM-4.5-AirX")
            ]
        case .volcengine:
            return []
        case .kimi:
            return [
                RemoteModelOption(id: "moonshot-v1-8k", title: "Moonshot V1 8K"),
                RemoteModelOption(id: "moonshot-v1-32k", title: "Moonshot V1 32K"),
                RemoteModelOption(id: "moonshot-v1-auto", title: "Moonshot V1 Auto")
            ]
        case .lmStudio:
            return [
                RemoteModelOption(id: "qwen2.5-14b-instruct", title: "Qwen2.5 14B"),
                RemoteModelOption(id: "llama3.1", title: "Llama 3.1 8B")
            ]
        case .minimax:
            return [
                RemoteModelOption(id: "MiniMax-Text-01", title: "MiniMax Text 01"),
                RemoteModelOption(id: "MiniMax-M2", title: "MiniMax M2"),
                RemoteModelOption(id: "MiniMax-M2.1-Lightning", title: "MiniMax M2.1 Lightning")
            ]
        case .aliyunBailian:
            return [
                RemoteModelOption(id: "qwen-plus", title: "Qwen Plus"),
                RemoteModelOption(id: "qwen-turbo", title: "Qwen Turbo")
            ]
        }
    }

    var advancedModelOptions: [RemoteModelOption] {
        switch self {
        case .anthropic:
            return [
                RemoteModelOption(id: "claude-opus-4-6", title: "Claude Opus 4.6"),
                RemoteModelOption(id: "claude-opus-4-5-20251101", title: "Claude Opus 4.5")
            ]
        case .google:
            return [
                RemoteModelOption(id: "gemini-2.5-flash", title: "Gemini 2.5 Flash"),
                RemoteModelOption(id: "gemini-1.5-pro-002", title: "Gemini 1.5 Pro 002"),
                RemoteModelOption(id: "gemini-pro-latest", title: "Gemini Pro Latest")
            ]
        case .openAI:
            return [
                RemoteModelOption(id: "o4-mini", title: "o4-mini"),
                RemoteModelOption(id: "o4-mini-deep-research", title: "o4-mini Deep Research"),
                RemoteModelOption(id: "o3-pro", title: "o3-pro"),
                RemoteModelOption(id: "o3", title: "o3"),
                RemoteModelOption(id: "o3-deep-research", title: "o3 Deep Research"),
                RemoteModelOption(id: "o3-mini", title: "o3-mini"),
                RemoteModelOption(id: "o1-pro", title: "o1-pro"),
                RemoteModelOption(id: "o1", title: "o1"),
                RemoteModelOption(id: "gpt-4.1", title: "GPT-4.1"),
                RemoteModelOption(id: "gpt-4.1-mini", title: "GPT-4.1 mini"),
                RemoteModelOption(id: "gpt-4o", title: "GPT-4o"),
                RemoteModelOption(id: "gpt-4o-search-preview", title: "GPT-4o Search Preview"),
                RemoteModelOption(id: "gpt-4o-2024-11-20", title: "GPT-4o 1120"),
                RemoteModelOption(id: "gpt-4o-2024-05-13", title: "GPT-4o 0513"),
                RemoteModelOption(id: "gpt-4-turbo", title: "GPT-4 Turbo"),
                RemoteModelOption(id: "gpt-4", title: "GPT-4"),
                RemoteModelOption(id: "gpt-4-0613", title: "GPT-4 0613")
            ]
        case .ollama:
            return [
                RemoteModelOption(id: "gpt-oss:120b", title: "GPT-OSS 120B"),
                RemoteModelOption(id: "llama3.1:70b", title: "Llama 3.1 70B"),
                RemoteModelOption(id: "mixtral:8x22b", title: "Mixtral 8x22B")
            ]
        case .deepseek:
            return [RemoteModelOption(id: "deepseek-reasoner", title: "DeepSeek V3.2 Thinking")]
        case .openrouter:
            return [
                RemoteModelOption(id: "openai/gpt-4.1", title: "GPT-4.1"),
                RemoteModelOption(id: "deepseek/deepseek-r1", title: "DeepSeek R1"),
                RemoteModelOption(id: "anthropic/claude-3.5-sonnet", title: "Claude 3.5 Sonnet")
            ]
        case .grok:
            return [
                RemoteModelOption(id: "grok-4-1-fast-reasoning", title: "Grok 4.1 Fast"),
                RemoteModelOption(id: "grok-code-fast-1", title: "Grok Code Fast 1")
            ]
        case .zai:
            return [
                RemoteModelOption(id: "glm-4.7", title: "GLM-4.7"),
                RemoteModelOption(id: "glm-4.6v", title: "GLM-4.6V")
            ]
        case .volcengine:
            return []
        case .kimi:
            return [
                RemoteModelOption(id: "kimi-k2-thinking", title: "Kimi K2 Thinking"),
                RemoteModelOption(id: "moonshot-v1-128k", title: "Moonshot V1 128K")
            ]
        case .lmStudio:
            return [RemoteModelOption(id: "qwen2.5-14b-instruct", title: "Qwen2.5 14B")]
        case .minimax:
            return [
                RemoteModelOption(id: "MiniMax-M2-Stable", title: "MiniMax M2 Stable"),
                RemoteModelOption(id: "MiniMax-M2.1", title: "MiniMax M2.1")
            ]
        case .aliyunBailian:
            return [
                RemoteModelOption(id: "qwen-max", title: "Qwen Max"),
                RemoteModelOption(id: "qwq-plus", title: "QwQ Plus")
            ]
        }
    }
}
