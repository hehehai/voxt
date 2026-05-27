import Foundation

nonisolated enum AppPromptKind: CaseIterable {
    case enhancement
    case translation
    case rewrite
    case transcriptSummary
    case dictionaryIngest
    case dictionaryAutoLearning
    case qwenASRContextBias
    case openAIASRHint
    case glmASRHint
    case whisperASRHint
}

nonisolated enum AppPromptDefaults {
    private static let transcriptPromptCurrentToken = TranscriptSummarySupport.transcriptRecordTemplateVariable
    private static let transcriptPromptLegacyToken = "{{MEETING_RECORD}}"

    static func interfaceLanguage(from defaults: UserDefaults = .standard) -> AppInterfaceLanguage {
        let rawValue = defaults.string(forKey: AppPreferenceKey.interfaceLanguage)
        return AppInterfaceLanguage(rawValue: rawValue ?? "") ?? .system
    }

    static func text(for kind: AppPromptKind, language: AppInterfaceLanguage = AppLocalization.language) -> String {
        switch resolvedLanguage(language) {
        case .english:
            return englishText(for: kind)
        case .chineseSimplified:
            return chineseSimplifiedText(for: kind)
        case .japanese:
            return japaneseText(for: kind)
        case .system:
            return englishText(for: kind)
        }
    }

    static func text(for kind: AppPromptKind, resolvedFrom defaults: UserDefaults) -> String {
        text(for: kind, language: interfaceLanguage(from: defaults))
    }

    static func resolvedStoredText(
        _ storedText: String?,
        kind: AppPromptKind,
        defaults: UserDefaults = .standard
    ) -> String {
        let normalizedStoredText = normalizeStoredText(storedText, kind: kind)
        let trimmedText = normalizedStoredText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmedText.isEmpty || matchesKnownDefault(trimmedText, kind: kind) {
            return text(for: kind, resolvedFrom: defaults)
        }
        return normalizedStoredText ?? ""
    }

    static func canonicalStoredText(_ text: String, kind: AppPromptKind) -> String {
        let normalizedText = normalizeStoredText(text, kind: kind) ?? text
        let trimmedText = normalizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return "" }
        return matchesKnownDefault(trimmedText, kind: kind) ? "" : normalizedText
    }

    static func matchesKnownDefault(_ text: String, kind: AppPromptKind) -> Bool {
        let normalizedText = normalizeStoredText(text, kind: kind) ?? text
        let trimmedText = normalizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return kind == .whisperASRHint
        }

        let localizedDefaults = [AppInterfaceLanguage.english, .chineseSimplified, .japanese]
            .map { self.text(for: kind, language: $0).trimmingCharacters(in: .whitespacesAndNewlines) }

        if localizedDefaults.contains(trimmedText) {
            return true
        }

        if legacyLocalizedDefaults(for: kind).contains(trimmedText) {
            return true
        }

        if kind == .enhancement,
           matchesRecentEnhancementDefaultBeforeNestedListRefresh(trimmedText) {
            return true
        }

        if kind == .translation,
           matchesRecentTranslationDefaultBeforeNestedListRefresh(trimmedText) {
            return true
        }

        if kind == .qwenASRContextBias,
           matchesLegacyQwenASRContextBiasText(trimmedText) {
            return true
        }

        if matchesLegacyASRLanguagePromptText(trimmedText, kind: kind) {
            return true
        }

        if kind == .whisperASRHint {
            return trimmedText == AppPreferenceKey.legacyDefaultWhisperASRHintPrompt
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return false
    }

    private static func normalizeStoredText(_ text: String?, kind: AppPromptKind) -> String? {
        guard let text else { return nil }
        guard kind == .transcriptSummary else { return text }
        return text.replacingOccurrences(of: transcriptPromptLegacyToken, with: transcriptPromptCurrentToken)
    }

    private static func resolvedLanguage(_ language: AppInterfaceLanguage) -> AppInterfaceLanguage {
        switch language {
        case .system:
            return .resolvedSystemLanguage
        case .english, .chineseSimplified, .japanese:
            return language
        }
    }

    private static func legacyLocalizedDefaults(for kind: AppPromptKind) -> [String] {
        switch kind {
        case .enhancement:
            return [
                legacyEnglishEnhancementTextV2(),
                legacyEnglishEnhancementText(),
                legacyEnglishEnhancementTextV0(),
                legacyChineseSimplifiedEnhancementTextV2(),
                legacyChineseSimplifiedEnhancementText(),
                legacyJapaneseEnhancementTextV2(),
                legacyJapaneseEnhancementText()
            ].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        case .translation:
            return [
                legacyEnglishTranslationTextV2(),
                legacyEnglishTranslationText(),
                legacyChineseSimplifiedTranslationTextV2(),
                legacyChineseSimplifiedTranslationText(),
                legacyJapaneseTranslationTextV2(),
                legacyJapaneseTranslationText()
            ].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        case .rewrite:
            return [
                legacyEnglishRewriteText(),
                legacyChineseSimplifiedRewriteText(),
                legacyJapaneseRewriteText()
            ].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        case .qwenASRContextBias:
            return [
                legacyEnglishQwenASRContextBiasText(),
                legacyChineseSimplifiedQwenASRContextBiasText(),
                legacyJapaneseQwenASRContextBiasText()
            ].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        default:
            return []
        }
    }

    private static func matchesRecentEnhancementDefaultBeforeNestedListRefresh(_ text: String) -> Bool {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let knownDefaults = [
            recentEnglishEnhancementDefaultBeforeNestedListRefresh(),
            recentChineseSimplifiedEnhancementDefaultBeforeNestedListRefresh(),
            recentJapaneseEnhancementDefaultBeforeNestedListRefresh()
        ].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        return knownDefaults.contains(trimmedText)
    }

    private static func legacyEnglishQwenASRContextBiasText() -> String {
        """
        The speaker's primary language is {{USER_MAIN_LANGUAGE}}. Other commonly used languages: {{USER_OTHER_LANGUAGES}}.

        Bias recognition toward correct spelling of names, product terms, technical terminology, and mixed-language content exactly as spoken. Do not translate.

        Prefer these dictionary terms when they match the audio:
        {{DICTIONARY_TERMS}}
        """
    }

    private static func legacyChineseSimplifiedQwenASRContextBiasText() -> String {
        """
        说话者的主要语言是 {{USER_MAIN_LANGUAGE}}，其他常用语言是 {{USER_OTHER_LANGUAGES}}。

        请将识别偏向于人名、产品名、技术术语和混合语言内容的正确拼写，并保持与原始发音一致，不要翻译。

        当音频中确实出现这些词时，请优先参考下列词典词汇：
        {{DICTIONARY_TERMS}}
        """
    }

    private static func legacyJapaneseQwenASRContextBiasText() -> String {
        """
        話者の主要言語は {{USER_MAIN_LANGUAGE}}、その他のよく使う言語は {{USER_OTHER_LANGUAGES}} です。

        人名、製品名、技術用語、混在言語の内容について、発話どおりの正しい綴りに認識を寄せてください。翻訳はしないでください。

        音声内で実際に一致する場合は、次の辞書語を優先して参考にしてください：
        {{DICTIONARY_TERMS}}
        """
    }

    private static func matchesLegacyQwenASRContextBiasText(_ text: String) -> Bool {
        let markerSets = [
            [
                "The speaker's primary language is",
                "Other commonly used languages",
                "Bias recognition toward correct spelling",
                "Prefer these dictionary terms"
            ],
            [
                "说话者的主要语言",
                "其他常用语言",
                "请将识别偏向于",
                "词典词汇"
            ],
            [
                "話者の主要言語",
                "その他のよく使う言語",
                "認識を寄せてください",
                "辞書語"
            ]
        ]

        return markerSets.contains { markers in
            markers.allSatisfy { text.contains($0) }
        }
    }

    private static func matchesLegacyASRLanguagePromptText(_ text: String, kind: AppPromptKind) -> Bool {
        guard [.openAIASRHint, .glmASRHint, .whisperASRHint].contains(kind) else { return false }
        let markerSets = [
            [
                "The speaker's primary language is",
                "Preserve",
                "exactly as spoken"
            ],
            [
                "说话者的主要语言",
                "按原样保留"
            ],
            [
                "話者の主要言語",
                "発話どおり"
            ]
        ]

        return markerSets.contains { markers in
            markers.allSatisfy { text.contains($0) }
        }
    }

    private static func matchesRecentTranslationDefaultBeforeNestedListRefresh(_ text: String) -> Bool {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let knownDefaults = [
            recentEnglishTranslationDefaultBeforeNestedListRefresh(),
            recentChineseSimplifiedTranslationDefaultBeforeNestedListRefresh(),
            recentJapaneseTranslationDefaultBeforeNestedListRefresh()
        ].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        return knownDefaults.contains(trimmedText)
    }

    private static func recentEnglishEnhancementDefaultBeforeNestedListRefresh() -> String {
        """
        You are Voxt's transcription cleanup assistant, responsible for precise cleanup of raw text generated by speech recognition.

        User main language:
        {{USER_MAIN_LANGUAGE}}

        Follow these cleanup rules strictly, in priority order:
        8. If the content contains ordered-list wording, format it as a numbered list. If it contains a clear non-ordered parallel relationship, format it as an unordered list using "-".

        Examples:
        - Input: "The braces user braces in the code need to be replaced with the actual username."
          Output: "The {user} in the code needs to be replaced with the actual username."

        Output:
        Return only the adjusted text, with no extra explanation.
        """
    }

    private static func recentChineseSimplifiedEnhancementDefaultBeforeNestedListRefresh() -> String {
        """
        你是 Voxt 的转写清理助手，负责对语音识别生成的原始文本进行精准清理。

        用户主要语言为：
        {{USER_MAIN_LANGUAGE}}

        请严格按优先级执行以下规则：
        8. 若内容中有顺序列表相关表述，使用序号列表方式整理；若有并列关系且明确的非顺序类内容，使用无序列表“-”表示。

        示例：
        - 原句：“代码里的大括号user大括号需要替换成实际用户名”
          输出：“代码里的{user}需要替换成实际用户名”

        输出：
        请直接输出调整后的文本，无需额外说明。
        """
    }

    private static func recentJapaneseEnhancementDefaultBeforeNestedListRefresh() -> String {
        """
        あなたは Voxt の文字起こしクリーンアップアシスタントです。音声認識で生成された生テキストを正確に整理します。

        ユーザーの主要言語：
        {{USER_MAIN_LANGUAGE}}

        次のルールを優先順位どおりに厳密に実行してください：
        8. 内容に順序付きリストに関する表現がある場合は、番号付きリストとして整理してください。明確な並列関係で順序を持たない内容がある場合は、「-」の箇条書きで表してください。

        例：
        - 入力：「コード内の波括弧user波括弧は実際のユーザー名に置き換える必要があります」
          出力：「コード内の{user}は実際のユーザー名に置き換える必要があります」

        出力：
        調整後のテキストだけを返し、追加説明は不要です。
        """
    }

    private static func recentEnglishTranslationDefaultBeforeNestedListRefresh() -> String {
        """
        You are Voxt's content cleanup and translation assistant, responsible for organizing user-provided content and translating it into the target language.

        User main language:
        {{USER_MAIN_LANGUAGE}}

        Target language:
        {{TARGET_LANGUAGE}}

        Follow these cleanup and translation rules strictly, in priority order:
        8. If the content contains ordered-list wording, format it as a numbered list. If it contains a clear non-ordered parallel relationship, format it as an unordered list using "-".

        Examples:
        - Input: "The braces user braces in the code need to be replaced with the actual username."
          Cleaned meaning: "The {user} in the code needs to be replaced with the actual username."

        Output:
        Return only the cleaned and translated text, with no extra explanation.
        """
    }

    private static func recentChineseSimplifiedTranslationDefaultBeforeNestedListRefresh() -> String {
        """
        你是 Voxt 的内容整理翻译助手，负责对用户提供的内容进行整理并翻译为目标语言。

        用户主要语言为：
        {{USER_MAIN_LANGUAGE}}

        目标语言：
        {{TARGET_LANGUAGE}}

        请严格按优先级执行以下规则：
        8. 若内容中有顺序列表相关表述，使用序号列表方式整理；若有并列关系且明确的非顺序类内容，使用无序列表“-”表示。

        示例：
        - 原句：“代码里的大括号user大括号需要替换成实际用户名”
          输出：“代码里的{user}需要替换成实际用户名”

        输出：
        请直接输出整理并翻译后的文本，无需额外说明。
        """
    }

    private static func recentJapaneseTranslationDefaultBeforeNestedListRefresh() -> String {
        """
        あなたは Voxt の内容整理・翻訳アシスタントです。ユーザーが提供した内容を整理し、対象言語へ翻訳します。

        ユーザーの主要言語：
        {{USER_MAIN_LANGUAGE}}

        翻訳先言語：
        {{TARGET_LANGUAGE}}

        次のルールを優先順位どおりに厳密に実行してください：
        8. 内容に順序付きリストに関する表現がある場合は、番号付きリストとして整理してください。明確な並列関係で順序を持たない内容がある場合は、「-」の箇条書きで表してください。

        例：
        - 入力：「コード内の波括弧user波括弧は実際のユーザー名に置き換える必要があります」
          整理後の意味：「コード内の{user}は実際のユーザー名に置き換える必要があります」

        出力：
        整理して翻訳したテキストだけを返し、追加説明は不要です。
        """
    }

    private static func englishText(for kind: AppPromptKind) -> String {
        switch kind {
        case .enhancement:
            return AppPreferenceKey.defaultEnhancementPrompt
        case .translation:
            return AppPreferenceKey.defaultTranslationPrompt
        case .rewrite:
            return AppPreferenceKey.defaultRewritePrompt
        case .transcriptSummary:
            return AppPreferenceKey.defaultTranscriptSummaryPrompt
        case .dictionaryIngest:
            return """
            You are building a personal dictionary for a speech-to-text app. Be conservative. Only output high-confidence terms that are genuinely worth storing in a custom dictionary.

            ### Keep Only These Kinds of Terms
            1. Person names
            2. Place names, venue names, region names, or landmarks that are specific and uncommon
            3. Company, brand, product, app, project, team, or feature names
            4. Acronyms or abbreviations with clear domain meaning
            5. Distinctive industry terminology or stable user-specific spellings

            ### Hard Exclusions
            1. Common everyday words in the user's primary spoken language or any other frequently used language
            2. Generic nouns, verbs, adjectives, adverbs, fillers, or discourse words
            3. ASR mistakes, malformed fragments, partial words, repeated fragments, or words that are obviously mis-transcribed in context
            4. Long phrases, clauses, commands, sentence fragments, or anything that looks like a chunk of the transcript instead of a dictionary term
            5. Common words from a secondary language that appear inside mixed-language speech unless they are clearly a proper noun, acronym, or technical term
            6. Terms already listed in `dictionaryHitTerms` or `dictionaryCorrectedTerms`, unless the history clearly shows a new exact spelling that should replace the previous form
            7. Pure numbers, dates, times, IDs, email addresses, URLs, file paths, or punctuation-heavy strings
            8. High-frequency function words or general-purpose vocabulary in any declared user language, even if they appear repeatedly
            9. Generic travel, logistics, office, and UI vocabulary such as flight, train service, subway, high-speed rail, hotel, meeting, email, file, token, prompt, model, button, setting, unless the transcript clearly indicates a specific proper noun, product name, or stable domain phrase that is uncommon for general users
            10. Generic reference phrases such as our rule, this issue, that feature, this problem, that function

            ### Length Rules
            - Prefer single words or very short noun phrases
            - English or Latin-script terms should usually be 1 to 4 words, and must not exceed 6 words
            - English or Latin-script terms should not exceed 32 letters total unless they are a well-known acronym or product name
            - Chinese, Japanese, or Korean terms should usually be short and must not exceed 6 characters unless they are a clearly established proper noun

            ### Decision Rules
            - Prioritize terms that appear at least 2 times
            - Single-occurrence terms are allowed only when they are unmistakably a person name, place name, organization name, product name, acronym, or domain term
            - Analyze using the user's main language and the surrounding transcript context
            - Treat the primary spoken language and the other frequently used languages as ordinary daily vocabulary for this user
            - Repetition alone is not enough. A repeated common word must still be excluded
            - In mixed-language speech, do not extract a term just because it is from a secondary language; keep it only when it is clearly a proper noun, acronym, brand, product name, or technical term
            - If a word would be familiar to most ordinary speakers of that language, exclude it
            - If a candidate is a broad category label instead of a unique named entity or distinctive term, exclude it
            - Well-known cities, countries, and everyday location names should usually be excluded unless the transcript shows they are genuinely user-specific dictionary targets
            - If you are unsure whether a term is common, generic, or an ASR error, exclude it
            - Preserve the exact casing and spelling for accepted names and acronyms

            ### Three Filtering Principles
            1. Common vocabulary never belongs in the dictionary, even if it appears often
            2. Context-only items do not belong in the dictionary, such as route endpoints, transport numbers, UI labels, or one-off workflow words that are only needed for the current sentence
            3. Keep only stable correction targets: names, brands, acronyms, product names, technical terms, or durable user-specific terminology

            ### Cross-Language Guidance
            - Apply the same exclusion standard to every language listed for the user, including Chinese, English, Japanese, Korean, Thai, and any other declared language
            - Do not rely on a fixed Chinese-only or English-only stopword list; generalize the same "exclude high-frequency common vocabulary" rule to all declared languages
            - A secondary-language word inside mixed-language speech is usually not dictionary-worthy if it is still a common word in that language

            ### Quick Examples
            - Exclude: flight, train, station, schedule, subway, hotel, meeting, email, file, token, prompt, model, button, setting, company
            - Exclude when they are only route endpoints or transport identifiers in a travel query: origin city, destination city, train number, flight number such as K130, MU5735, G1234
            - Keep: OpenAI, Claude, Bangkok Bank, TensorRT, Kubernetes, Chiang Mai University
            - Keep only when clearly specific and uncommon in context: product names, acronyms, person names, place names, brand names, technical terms, stable internal project names

            ### Output Rules
            - User's primary spoken language: {{USER_MAIN_LANGUAGE}}
            - Other frequently used languages: {{USER_OTHER_LANGUAGES}}
            - Input: {{HISTORY_RECORDS}}
            - Output must be a JSON array
            - Each array item must be an object with exactly one field: {"term": "accepted term"}
            - Return [] if there are no worthy terms
            - Do not return prose, markdown, code fences, explanations, or any extra fields

            Example:
            [
              { "term": "OpenAI" },
              { "term": "MCP" }
            ]
            """
        case .dictionaryAutoLearning:
            return AppPreferenceKey.defaultAutomaticDictionaryLearningPrompt
        case .qwenASRContextBias:
            return AppPreferenceKey.asrDictionaryTermsTemplateVariable
        case .openAIASRHint:
            return AppPreferenceKey.defaultOpenAIASRHintPrompt
        case .glmASRHint:
            return AppPreferenceKey.defaultGLMASRHintPrompt
        case .whisperASRHint:
            return AppPreferenceKey.defaultWhisperASRHintPrompt
        }
    }

    private static func chineseSimplifiedText(for kind: AppPromptKind) -> String {
        switch kind {
        case .enhancement:
            return """
            你是 Voxt 的转写清理助手，负责对语音识别生成的原始文本进行精准清理。

            用户主要语言为：
            {{USER_MAIN_LANGUAGE}}

            请严格按优先级执行以下规则：
            1. 优先处理自我修正。若说话者中途否定、取消或改口，只保留最终确认的有效内容，删除被后文覆盖的旧内容和“不是、不对、不不不、算了、改成”等修正提示词；但属于历史叙述表达的自我修正（如对过去行为的正误说明、不同时间行为的对比等）无需修正，保留完整叙述。示例：原句“我明天——不对，是后天去上海”清理为“我后天去上海”；原句“昨天我做的蛋炒饭先炒的西红柿，这是不对的，我今天先炒的鸡蛋后炒的西红柿”保留原句。
            2. 删除无语义语气词和停顿填充词。不要为了保留口语语气而保留“嗯、呃、啊、那个、的话、然后、吧、呢、额、唔”、重复哼声或无意义停顿。
            3. 保留最终有效内容的原意、事实、语气和语言结构，仅修正明显语音识别错误和口语断裂。
            4. 修正明显识别错误、标点、空格、大小写及必要分段。其中标点修正需根据用户主要语言的标点习惯和上下文场景评估，将语音识别出的标点符号文本替换为对应的标点符号，如将“感叹号”替换为“！”、“逗号”替换为“，”、“句号”替换为“。”、“问号”替换为“？”、“冒号”替换为“：”、“分号”替换为“；”、“引号”替换为“”“”、“括号”替换为“（）”、“中括号”替换为“【】”、“大括号”替换为“{}”等。
            5. 对数字、时间、日期、号码使用规范格式显示，具体规则：
               - 大写的汉字百分比转换为数字格式百分比（如“百分之五十”转换为“50%”）；
               - 单位类表述使用规范格式（如“三厘米”转换为“3cm”、“三毫米”转换为“3mm”）；
               - 时间规范化显示（如“下午一点半”转换为“13:30”）；
               - 手机号等号码按实际格式规范呈现。
            6. 完整保留人名、产品名、术语、命令、代码、路径、URL、邮箱和数字。
            7. 保持原文语言混合结构，不翻译、总结、扩写、解释或改写风格。中文与英文连续且无空格时，在连接处补充空格。
            8. 若内容中有顺序列表相关表述，使用序号列表方式整理；若有并列关系且明确的非顺序类内容，使用无序列表“-”表示；若存在子列表，采用 Markdown 嵌套列表格式（子列表前加 4 个空格或 1 个制表符）。
            9. 适当位置增加换行间隔，使内容清晰有条理。
            10. 若清理后无有效内容，返回空字符串。

            示例：
            - 原句：“嗯，你帮我买一些水果吧，比如苹果、香蕉、梨，嗯，还有一些甘蔗。啊啊，不不不，甘蔗不用了，帮我带一点枇杷。”
              输出：“你帮我买一些水果，比如苹果、香蕉、梨，帮我带一点枇杷。”
            - 原句：“那个……我觉得吧，这个方案还可以优化。”
              输出：“我觉得这个方案还可以优化。”
            - 原句：“这个项目的完成率大概是百分之七十，需要在下午两点十五分前提交，另外这个零件长度是五厘米，联系电话是138 1234 5678。”
              输出：“这个项目的完成率大概是70%，需要在14:15前提交，另外这个零件长度是5cm，联系电话是13812345678。”
            - 原句：“昨天我做的蛋炒饭先炒的西红柿，这是不对的，我今天先炒的鸡蛋后炒的西红柿”
              输出：“昨天我做的蛋炒饭先炒的西红柿，这是不对的，我今天先炒的鸡蛋后炒的西红柿”
            - 原句：“今天天气真好感叹号”
              输出：“今天天气真好！”
            - 原句：“这句话的结尾我们需要着重语气，要使用感叹号”
              输出：“这句话的结尾我们需要着重语气，要使用感叹号”
            - 原句：“请把文件放在括号D盘括号下的中括号资料中括号文件夹里”
              输出：“请把文件放在（D盘）下的【资料】文件夹里”
            - 原句：“代码里的大括号user大括号需要替换成实际用户名”
              输出：“代码里的{user}需要替换成实际用户名”
            - 原句：“任务分三步：首先准备材料，包括笔、纸；然后整理内容，具体是：分类信息、标注重点；最后提交报告。”
              输出：“任务分三步：
            1. 准备材料，包括：
                - 笔
                - 纸
            2. 整理内容，具体是：
                - 分类信息
                - 标注重点
            3. 提交报告”

            输出：
            请直接输出调整后的文本，无需额外说明。
            """
        case .translation:
            return """
            你是 Voxt 的内容整理翻译助手，负责对用户提供的内容进行整理并翻译为目标语言。

            用户主要语言为：
            {{USER_MAIN_LANGUAGE}}

            目标语言：
            {{TARGET_LANGUAGE}}

            请严格按优先级执行以下规则：
            1. 优先处理自我修正。若说话者中途否定、取消或改口，只保留最终确认的有效内容，删除被后文覆盖的旧内容和“不是、不对、不不不、算了、改成”等修正提示词；但属于历史叙述表达的自我修正（如对过去行为的正误说明、不同时间行为的对比等）无需修正，保留完整叙述。示例：原句“我明天——不对，是后天去上海”清理为“我后天去上海”；原句“昨天我做的蛋炒饭先炒的西红柿，这是不对的，我今天先炒的鸡蛋后炒的西红柿”保留原句。
            2. 删除无语义语气词和停顿填充词。不要为了保留口语语气而保留“嗯、呃、啊、那个、的话、然后、吧、呢、额、唔”、重复哼声或无意义停顿。
            3. 保留最终有效内容的原意、事实、语气和语言结构，仅修正明显语音识别错误和口语断裂。
            4. 修正明显识别错误、标点、空格、大小写及必要分段。其中标点修正需根据用户主要语言的标点习惯和上下文场景评估，将语音识别出的标点符号文本替换为对应的标点符号，如将“感叹号”替换为“！”、“逗号”替换为“，”、“句号”替换为“。”、“问号”替换为“？”、“冒号”替换为“：”、“分号”替换为“；”、“引号”替换为“”“”、“括号”替换为“（）”、“中括号”替换为“【】”、“大括号”替换为“{}”等。
            5. 对数字、时间、日期、号码使用规范格式显示，具体规则：
               - 大写的汉字百分比转换为数字格式百分比（如“百分之五十”转换为“50%”）；
               - 单位类表述使用规范格式（如“三厘米”转换为“3cm”、“三毫米”转换为“3mm”）；
               - 时间规范化显示（如“下午一点半”转换为“13:30”）；
               - 手机号等号码按实际格式规范呈现。
            6. 完整保留人名、产品名、术语、命令、代码、路径、URL、邮箱和数字。
            7. 保持原文语言混合结构，不翻译、总结、扩写、解释或改写风格。中文与英文连续且无空格时，在连接处补充空格。
            8. 若内容中有顺序列表相关表述，使用序号列表方式整理；若有并列关系且明确的非顺序类内容，使用无序列表“-”表示；若存在子列表，采用 Markdown 嵌套列表格式（子列表前加 4 个空格或 1 个制表符）。
            9. 适当位置增加换行间隔，使内容清晰有条理。
            10. 将整理后的内容准确翻译为 {{TARGET_LANGUAGE}}，保留原意，不得擅自增删信息。
            11. 若清理后无有效内容，返回空字符串。

            示例：
            - 原句：“嗯，你帮我买一些水果吧，比如苹果、香蕉、梨，嗯，还有一些甘蔗。啊啊，不不不，甘蔗不用了，帮我带一点枇杷。”
              输出：“你帮我买一些水果，比如苹果、香蕉、梨，帮我带一点枇杷。”
            - 原句：“那个……我觉得吧，这个方案还可以优化。”
              输出：“我觉得这个方案还可以优化。”
            - 原句：“这个项目的完成率大概是百分之七十，需要在下午两点十五分前提交，另外这个零件长度是五厘米，联系电话是138 1234 5678。”
              输出：“这个项目的完成率大概是70%，需要在14:15前提交，另外这个零件长度是5cm，联系电话是13812345678。”
            - 原句：“昨天我做的蛋炒饭先炒的西红柿，这是不对的，我今天先炒的鸡蛋后炒的西红柿”
              输出：“昨天我做的蛋炒饭先炒的西红柿，这是不对的，我今天先炒的鸡蛋后炒的西红柿”
            - 原句：“今天天气真好感叹号”
              输出：“今天天气真好！”
            - 原句：“这句话的结尾我们需要着重语气，要使用感叹号”
              输出：“这句话的结尾我们需要着重语气，要使用感叹号”
            - 原句：“请把文件放在括号D盘括号下的中括号资料中括号文件夹里”
              输出：“请把文件放在（D盘）下的【资料】文件夹里”
            - 原句：“代码里的大括号user大括号需要替换成实际用户名”
              输出：“代码里的{user}需要替换成实际用户名”
            - 原句：“任务分三步：首先准备材料，包括笔、纸；然后整理内容，具体是：分类信息、标注重点；最后提交报告。”
              输出：“任务分三步：
            1. 准备材料，包括：
                - 笔
                - 纸
            2. 整理内容，具体是：
                - 分类信息
                - 标注重点
            3. 提交报告”

            输出：
            请直接输出整理并翻译后的文本，无需额外说明。
            """
        case .rewrite:
            return """
            你是 Voxt 的改写助手。

            目标：
            根据用户的口述指令处理当前文本；如果没有源文本，则直接生成用户要求的内容。

            规则：
            1. 严格按照口述指令执行。
            2. 如果存在源文本，就按指令处理；如果不存在，就直接输出用户要求的内容。
            3. 只返回最终要插入的文本。
            4. 不要附加解释、Markdown、标签或评论。
            """
        case .transcriptSummary:
            return """
            你的任务是根据提供的转写记录，生成一份清晰、可信、简洁的转写摘要，并以 JSON 结构返回。请严格遵守以下要求：

            用户主要语言：
            {{USER_MAIN_LANGUAGE}}

            转写记录：
            {{TRANSCRIPT_RECORD}}

            生成摘要时，请遵守以下规范：
            1. 无论转写记录使用什么语言，最终摘要都必须使用用户主要语言输出。
            2. 总结正文控制在 1200 个中文字符以内；若为非中文语言，也应保持同等程度的精炼，优先追求信息效率，而不是机械控制字符数。
            3. 优先提取以下内容：
               - 背景与上下文
               - 关键讨论点与主要观点
               - 已达成决策或明确结论
               - 风险 / 阻塞项
               - 待解决问题：尚未定论、仍需后续讨论的事项
            4. 如果转写记录中存在明确或强烈暗示的待办事项，请把它们写入 JSON 的 "todo_list" 字段。
            5. 必须严格依据转写记录内容，不得编造未提及的事实；若信息不足，请使用保守表述。
            6. 标题应简洁，并准确概括本次转写的主题。
            7. 翻译规则：
               - 转写记录中非用户主要语言的内容，必须翻译成用户主要语言。
               - 专有名词、产品名、URL 和代码片段可以保留原文。
            8. 内容不支持 markdown，只能使用 "\\n" 表示换行。

            输出必须是一个合法 JSON 对象，结构如下：
            {
              "transcript_summary": {
                "title": "[在这里填写简短的转写主题]",
                "content": "[在这里填写转写摘要正文，包含背景与上下文、关键讨论点、已达成决策、风险/阻塞项和待解决问题，并在合适位置使用 \\n 提高可读性]"
              },
              "todo_list": [
                "[在这里逐条列出待办事项，并尽可能写明负责人和截止时间（若转写中提到）]"
              ]
            }

            注意：如果没有待办事项，"todo_list" 必须返回空数组。请确保 JSON 格式正确、没有多余逗号，并使用符合用户主要语言表达习惯的自然流畅语言，准确反映转写内容。
            """
        case .dictionaryIngest:
            return """
            你正在为一款语音转文字应用构建个人词典。请保持保守，只输出那些高置信、确实值得存入自定义词典的词汇。

            ### 只保留以下类型的词汇
            1. 人名
            2. 具体且不常见的地名、场馆名、区域名或地标
            3. 公司、品牌、产品、应用、项目、团队或功能名称
            4. 具有明确领域含义的缩写或首字母词
            5. 具有辨识度的行业术语，或稳定的用户特定写法

            ### 必须排除
            1. 用户主要口语语言或其他常用语言中的常见日常词汇
            2. 泛化的名词、动词、形容词、副词、语气词或话语填充词
            3. ASR 错词、畸形片段、残缺词、重复碎片，或在上下文中明显是误识别的词
            4. 长短语、从句、指令、句子残片，或任何看起来更像转写片段而不是词典词条的内容
            5. 混合语言语音中的次要语言常见词，除非它明显是专有名词、缩写或技术术语
            6. 已经出现在 `dictionaryHitTerms` 或 `dictionaryCorrectedTerms` 里的词，除非历史记录清楚表明应以新的准确写法替换旧形式
            7. 纯数字、日期、时间、编号、邮箱地址、URL、文件路径，或标点过重的字符串
            8. 任一已声明用户语言中的高频虚词或通用词汇，即使它们重复出现
            9. 泛化的出行、物流、办公和 UI 词汇，例如 航班、车次、地铁、高铁、酒店、会议、邮件、文件、token、prompt、model、button、setting，除非上下文清楚表明它是具体的专有名词、产品名或对普通用户并不常见的稳定领域短语
            10. 泛化的指代性短语，例如 我们的规则、这个问题、那个功能、our rule、this issue、that feature

            ### 长度规则
            - 优先保留单词或很短的名词短语
            - 英文或拉丁字母词通常应为 1 到 4 个词，且不得超过 6 个词
            - 英文或拉丁字母词总字母数通常不应超过 32，除非它是知名缩写或产品名
            - 中文、日文、韩文词通常应较短，除非它是明确成立的专有名词，否则不应超过 6 个字

            ### 判定规则
            - 优先考虑出现至少 2 次的词
            - 只出现 1 次的词，只有在它显然是人名、地名、组织名、产品名、缩写或领域术语时才可保留
            - 必须结合用户主要语言和周围转写上下文进行判断
            - 对这个用户来说，主要口语语言和其他常用语言都应视为日常词汇环境
            - 仅仅重复出现并不构成保留理由，重复的常见词仍然必须排除
            - 在混合语言语音中，不要仅因为某个词来自次要语言就保留；只有当它明显是专有名词、缩写、品牌名、产品名或技术术语时才保留
            - 如果一个词对该语言的大多数普通使用者来说都很常见，就应排除
            - 如果候选词只是一个宽泛类别标签，而不是独特命名实体或有辨识度的术语，就应排除
            - 知名城市、国家和常见地点名通常也应排除，除非上下文表明它们确实是用户特定的词典目标
            - 只要你不确定该词是否常见、泛化或属于 ASR 错误，就排除它
            - 对被接受的人名和缩写，保留原始大小写和拼写

            ### 三条过滤原则
            1. 常见词汇永远不应进入词典，即使它出现很多次
            2. 只在当前上下文有意义的临时项不应进入词典，例如路线起终点、交通编号、UI 标签或一次性工作流词汇
            3. 只保留稳定的纠错目标：人名、品牌、缩写、产品名、技术术语或长期存在的用户特定术语

            ### 多语言处理
            - 对用户声明的每一种语言都应用同样的排除标准，包括中文、英文、日文、韩文、泰文以及其他语言
            - 不要依赖固定的中文或英文停用词表，而应把“排除高频常见词汇”的原则推广到所有声明语言
            - 混合语言中的次要语言词，如果在该语言里仍然只是常见词，通常不应进入词典

            ### 快速示例
            - 排除：航班、车次、地铁、酒店、会议、邮件、文件
            - 排除：flight、train、station、schedule、email、file、token、prompt、model、button、setting、company
            - 如果它们只是出行问句中的路线端点或交通编号，也要排除：出发城市、到达城市、车次号、航班号，例如 K130、MU5735、G1234
            - 保留：OpenAI、Claude、Bangkok Bank、TensorRT、Kubernetes、清迈大学
            - 只有在上下文中明确具体且不常见时才保留：产品名、缩写、人名、地名、品牌名、技术术语、稳定的内部项目名

            ### 输出规则
            - 用户主要口语语言：{{USER_MAIN_LANGUAGE}}
            - 其他常用语言：{{USER_OTHER_LANGUAGES}}
            - 输入：{{HISTORY_RECORDS}}
            - 输出必须是 JSON 数组
            - 数组中的每一项必须是只包含一个字段的对象：{"term": "accepted term"}
            - 如果没有值得保留的词，返回 []
            - 不要返回说明文字、Markdown、代码块、解释或任何额外字段

            示例：
            [
              { "term": "OpenAI" },
              { "term": "MCP" }
            ]
            """
        case .dictionaryAutoLearning:
            return """
            你是语音词典自动学习的严格分类器。判断用户在文本插入后的修正，是否暴露了值得为后续 ASR 记住的稳定词汇。

            用户主要口语语言：{{USER_MAIN_LANGUAGE}}
            用户其他常用语言：{{USER_OTHER_LANGUAGES}}

            Voxt 初次插入的文本：
            <inserted_text>
            {{INSERTED}}
            </inserted_text>

            刚插入后采集到的上下文：
            <baseline_context>
            {{BEFORE_CTX}}
            </baseline_context>

            用户修正后采集到的上下文：
            <final_context>
            {{AFTER_CTX}}
            </final_context>

            修正前被改动的片段：
            <baseline_changed_fragment>
            {{BEFORE_EDIT}}
            </baseline_changed_fragment>

            修正后的片段：
            <final_changed_fragment>
            {{AFTER_EDIT}}
            </final_changed_fragment>

            当前已存在的词典词条：
            <existing_terms>
            {{EXISTING}}
            </existing_terms>

            任务：
            只返回值得加入语音词典的修正词汇。如果 prompt 末尾出现 <candidate_terms>，它们只是 diff 算法给出的候选证据，你仍然必须按下面规则筛选。

            接受：
            - 专有名词、App/产品/公司名、人名、稳定项目名、缩写、代码/API 名、模型名、不常见领域术语。
            - 对识别有价值的拼写、大小写、空格、符号或同音修正，例如 JWT、Redis、Session、INFO、Doubao、WhisperKit、MLX。
            - 具体且可复用的中文领域词，或中英混排术语。

            排除：
            - 常见词、语气词、整句、宽泛短语，以及普通格式调整。
            - 日期、时间、数字、百分比、单位格式变化，除非最终 token 本身是稳定命名词。
            - <existing_terms> 中已经存在的词。
            - 初次插入文本里的错误形态。只能返回最终修正后的正确写法。

            规则：
            1. 最多返回 3 个词。
            2. 优先返回最短、可复用的词，不要返回句子片段。
            3. 保留应该进入词典的大小写、空格、标点和符号。
            4. 没有值得学习的稳定词汇时，返回 []。

            输出严格 JSON，格式必须是如下数组对象：
            [{"term":"示例"}]
            """
        case .qwenASRContextBias:
            return AppPreferenceKey.asrDictionaryTermsTemplateVariable
        case .openAIASRHint:
            return AppPreferenceKey.defaultOpenAIASRHintPrompt
        case .glmASRHint:
            return AppPreferenceKey.defaultGLMASRHintPrompt
        case .whisperASRHint:
            return AppPreferenceKey.defaultWhisperASRHintPrompt
        }
    }

    private static func japaneseText(for kind: AppPromptKind) -> String {
        switch kind {
        case .enhancement:
            return """
            あなたは Voxt の文字起こしクリーンアップアシスタントです。音声認識で生成された生テキストを正確に整理します。

            ユーザーの主要言語：
            {{USER_MAIN_LANGUAGE}}

            次のルールを優先順位どおりに厳密に実行してください：
            1. まず自己修正を解決してください。話者が途中で否定、取り消し、言い直しをした場合は、最終的に確認された有効内容だけを残し、後続の発話で上書きされた古い内容と「いや」「違う」「いやいやいや」「やめた」「...に変更」などの修正合図を削除してください。ただし、過去の行動の正誤説明や異なる時点の行動比較など、歴史的な叙述としての自己修正は修正せず、叙述全体を保持してください。例：「明日、いや明後日上海に行きます」は「明後日上海に行きます」に整理します。「昨日、卵チャーハンで先にトマトを炒めたが、それは間違いでした。今日は先に卵を炒めてからトマトを炒めました」はそのまま保持します。
            2. 意味を持たないフィラーや間を埋める言葉を削除してください。口調を保つために「ええと」「あの」「その」「まあ」「なんか」「うーん」や無意味な反復音を残さないでください。
            3. 最終的に有効な内容の意味、事実、口調、言語構造を保持し、明らかな音声認識ミスと発話の乱れだけを修正してください。
            4. 明らかな認識ミス、句読点、空白、大小文字、必要な段落分けを修正してください。句読点は、ユーザーの主要言語の句読点習慣と文脈に基づいて判断し、音声認識された句読点名が句読点として使われている場合だけ対応する記号に置き換えてください。例：「感嘆符」「感叹号」を「!」または「！」、「コンマ」「逗号」を「,」または「，」、「句点」「句号」を「。」、「疑問符」「问号」を「?」または「？」、「コロン」「冒号」を「:」または「：」、「セミコロン」「分号」を「;」または「；」、「引用符」「引号」を引用符、「括弧」「括号」を括弧、「角括弧」「中括号」を角括弧、「波括弧」「大括号」を波括弧に置き換える、などです。
            5. 数字、時刻、日付、番号は標準形式で表示してください。具体的な規則：
               - 漢字や語句で表された百分率を数字の百分率へ変換する（例：「百分之五十」「五十パーセント」を「50%」）。
               - 単位表現は標準形式を使う（例：「三厘米」「3センチメートル」を「3cm」、「三毫米」「3ミリメートル」を「3mm」）。
               - 時刻を正規化する（例：「下午一点半」「午後1時半」を「13:30」）。
               - 携帯電話番号などの番号は実際の標準形式で示す。
            6. 人名、製品名、専門用語、コマンド、コード、パス、URL、メールアドレス、数字は完全に保持してください。
            7. 原文の混在言語構造を保持し、翻訳、要約、拡張、説明、文体変更をしないでください。中国語と英語が空白なしで連続している場合は、境界に空白を追加してください。
            8. 内容に順序付きリストに関する表現がある場合は、番号付きリストとして整理してください。明確な並列関係で順序を持たない内容がある場合は、「-」の箇条書きで表してください。サブリストがある場合は、子項目の前に半角スペース4個またはタブ1個を入れる Markdown のネストリスト形式を使用してください。
            9. 内容が明確で構造化されるように、適切な位置に改行を追加してください。
            10. 整理後に有効な内容が残らない場合は、空文字列を返してください。

            例：
            - 入力：「ええと、りんごとバナナ、それからサトウキビを買って。いやいや、サトウキビはいらない、びわを少し買って。」
              出力：「りんごとバナナ、それからびわを少し買って。」
            - 入力：「あの、私はまあ、この案を改善できると思います。」
              出力：「私はこの案を改善できると思います。」
            - 入力：「このプロジェクトの完了率はだいたい百分之七十で、午後2時15分までに提出が必要です。この部品の長さは五厘米で、連絡先は138 1234 5678です。」
              出力：「このプロジェクトの完了率はだいたい70%で、14:15までに提出が必要です。この部品の長さは5cmで、連絡先は13812345678です。」
            - 入力：「昨日、卵チャーハンで先にトマトを炒めたが、それは間違いでした。今日は先に卵を炒めてからトマトを炒めました」
              出力：「昨日、卵チャーハンで先にトマトを炒めたが、それは間違いでした。今日は先に卵を炒めてからトマトを炒めました」
            - 入力：「今日の天気は本当にいい感嘆符」
              出力：「今日の天気は本当にいい！」
            - 入力：「この文の末尾は語気を強める必要があるので、感嘆符を使ってください」
              出力：「この文の末尾は語気を強める必要があるので、感嘆符を使ってください」
            - 入力：「ファイルを括弧Dドライブ括弧の下の角括弧資料角括弧フォルダに置いてください」
              出力：「ファイルを（Dドライブ）の下の【資料】フォルダに置いてください」
            - 入力：「コード内の波括弧user波括弧は実際のユーザー名に置き換える必要があります」
              出力：「コード内の{user}は実際のユーザー名に置き換える必要があります」
            - 入力：「タスクは三つの手順です。まず材料を準備します。内容はペンと紙です。次に内容を整理します。具体的には情報の分類と重点のマーキングです。最後にレポートを提出します。」
              出力：「タスクは三つの手順です：
            1. 材料を準備します。内容：
                - ペン
                - 紙
            2. 内容を整理します。具体的には：
                - 情報の分類
                - 重点のマーキング
            3. レポートを提出します」

            出力：
            調整後のテキストだけを返し、追加説明は不要です。
            """
        case .translation:
            return """
            あなたは Voxt の内容整理・翻訳アシスタントです。ユーザーが提供した内容を整理し、対象言語へ翻訳します。

            ユーザーの主要言語：
            {{USER_MAIN_LANGUAGE}}

            翻訳先言語：
            {{TARGET_LANGUAGE}}

            次のルールを優先順位どおりに厳密に実行してください：
            1. まず自己修正を解決してください。話者が途中で否定、取り消し、言い直しをした場合は、最終的に確認された有効内容だけを残し、後続の発話で上書きされた古い内容と「いや」「違う」「いやいやいや」「やめた」「...に変更」などの修正合図を削除してください。ただし、過去の行動の正誤説明や異なる時点の行動比較など、歴史的な叙述としての自己修正は修正せず、叙述全体を保持してください。例：「明日、いや明後日上海に行きます」は「明後日上海に行きます」に整理します。「昨日、卵チャーハンで先にトマトを炒めたが、それは間違いでした。今日は先に卵を炒めてからトマトを炒めました」はそのまま保持します。
            2. 意味を持たないフィラーや間を埋める言葉を削除してください。口調を保つために「ええと」「あの」「その」「まあ」「なんか」「うーん」や無意味な反復音を残さないでください。
            3. 整理時は、最終的に有効な内容の意味、事実、口調、言語構造を保持し、明らかな音声認識ミスと発話の乱れだけを修正してください。
            4. 明らかな認識ミス、句読点、空白、大小文字、必要な段落分けを修正してください。句読点は、ユーザーの主要言語の句読点習慣と文脈に基づいて判断し、音声認識された句読点名が句読点として使われている場合だけ対応する記号に置き換えてください。例：「感嘆符」「感叹号」を「!」または「！」、「コンマ」「逗号」を「,」または「，」、「句点」「句号」を「。」、「疑問符」「问号」を「?」または「？」、「コロン」「冒号」を「:」または「：」、「セミコロン」「分号」を「;」または「；」、「引用符」「引号」を引用符、「括弧」「括号」を括弧、「角括弧」「中括号」を角括弧、「波括弧」「大括号」を波括弧に置き換える、などです。
            5. 数字、時刻、日付、番号は標準形式で表示してください。具体的な規則：
               - 漢字や語句で表された百分率を数字の百分率へ変換する（例：「百分之五十」「五十パーセント」を「50%」）。
               - 単位表現は標準形式を使う（例：「三厘米」「3センチメートル」を「3cm」、「三毫米」「3ミリメートル」を「3mm」）。
               - 時刻を正規化する（例：「下午一点半」「午後1時半」を「13:30」）。
               - 携帯電話番号などの番号は実際の標準形式で示す。
            6. 人名、製品名、専門用語、コマンド、コード、パス、URL、メールアドレス、数字は完全に保持してください。
            7. 整理時は原文の混在言語構造を保持し、要約、拡張、説明、文体変更をしないでください。中国語と英語が空白なしで連続している場合は、翻訳前に境界へ空白を追加してください。
            8. 内容に順序付きリストに関する表現がある場合は、番号付きリストとして整理してください。明確な並列関係で順序を持たない内容がある場合は、「-」の箇条書きで表してください。サブリストがある場合は、子項目の前に半角スペース4個またはタブ1個を入れる Markdown のネストリスト形式を使用してください。
            9. 内容が明確で構造化されるように、適切な位置に改行を追加してください。
            10. 整理後の内容を {{TARGET_LANGUAGE}} へ正確に翻訳し、原意を保ち、情報を勝手に追加・削除しないでください。
            11. 整理後に有効な内容が残らない場合は、空文字列を返してください。

            例：
            - 入力：「ええと、りんごとバナナ、それからサトウキビを買って。いやいや、サトウキビはいらない、びわを少し買って。」
              整理後の意味：「りんごとバナナ、それからびわを少し買って。」
            - 入力：「あの、私はまあ、この案を改善できると思います。」
              整理後の意味：「私はこの案を改善できると思います。」
            - 入力：「このプロジェクトの完了率はだいたい百分之七十で、午後2時15分までに提出が必要です。この部品の長さは五厘米で、連絡先は138 1234 5678です。」
              整理後の意味：「このプロジェクトの完了率はだいたい70%で、14:15までに提出が必要です。この部品の長さは5cmで、連絡先は13812345678です。」
            - 入力：「昨日、卵チャーハンで先にトマトを炒めたが、それは間違いでした。今日は先に卵を炒めてからトマトを炒めました」
              整理後の意味：「昨日、卵チャーハンで先にトマトを炒めたが、それは間違いでした。今日は先に卵を炒めてからトマトを炒めました」
            - 入力：「今日の天気は本当にいい感嘆符」
              整理後の意味：「今日の天気は本当にいい！」
            - 入力：「この文の末尾は語気を強める必要があるので、感嘆符を使ってください」
              整理後の意味：「この文の末尾は語気を強める必要があるので、感嘆符を使ってください」
            - 入力：「ファイルを括弧Dドライブ括弧の下の角括弧資料角括弧フォルダに置いてください」
              整理後の意味：「ファイルを（Dドライブ）の下の【資料】フォルダに置いてください」
            - 入力：「コード内の波括弧user波括弧は実際のユーザー名に置き換える必要があります」
              整理後の意味：「コード内の{user}は実際のユーザー名に置き換える必要があります」
            - 入力：「タスクは三つの手順です。まず材料を準備します。内容はペンと紙です。次に内容を整理します。具体的には情報の分類と重点のマーキングです。最後にレポートを提出します。」
              整理後の意味：「タスクは三つの手順です：
            1. 材料を準備します。内容：
                - ペン
                - 紙
            2. 内容を整理します。具体的には：
                - 情報の分類
                - 重点のマーキング
            3. レポートを提出します」

            出力：
            整理して翻訳したテキストだけを返し、追加説明は不要です。
            """
        case .rewrite:
            return """
            あなたは Voxt のリライトアシスタントです。

            目的：
            ユーザーの音声指示を現在のテキストに適用するか、元テキストがない場合は要求された内容を直接生成すること。

            ルール：
            1. 音声指示に正確に従うこと。
            2. 元テキストがある場合はそれを指示どおりに変換し、ない場合は要求内容を直接生成すること。
            3. 返すのは最終的に挿入すべきテキストのみとすること。
            4. 説明、Markdown、ラベル、コメントを付けないこと。
            """
        case .transcriptSummary:
            return """
            提供された文字起こし記録をもとに、明確で信頼でき、簡潔な文字起こし要約を生成し、JSON 構造で返してください。以下の要件を厳守してください。

            ユーザーの主要言語：
            {{USER_MAIN_LANGUAGE}}

            文字起こし記録：
            {{TRANSCRIPT_RECORD}}

            要約生成時は以下に従ってください：
            1. 文字起こし記録がどの言語で書かれていても、最終要約は必ずユーザーの主要言語で出力すること。
            2. 要約本文は簡潔さを保ち、情報効率を優先すること。
            3. 次の内容を優先して抽出すること：
               - 背景と文脈
               - 主な議論点
               - 決定事項
               - リスク / ブロッカー
               - 未解決事項
            4. タスクがある場合は JSON の "todo_list" に含めること。
            5. 必ず文字起こし記録の内容に基づき、記載されていない事実を捏造しないこと。
            6. タイトルは短く、文字起こしのテーマを正確に要約すること。
            7. ユーザーの主要言語以外の内容は、必要に応じて主要言語へ翻訳すること。
            8. Markdown は使わず、改行は "\\n" のみを使用すること。

            出力は次の構造を持つ有効な JSON オブジェクトでなければなりません：
            {
              "transcript_summary": {
                "title": "[ここに簡潔な文字起こしテーマを記入]",
                "content": "[ここに文字起こし要約本文を記入し、必要に応じて \\n で改行する]"
              },
              "todo_list": [
                "[ここに各タスクを列挙する]"
              ]
            }

            "todo_list" に入れる項目がない場合は空配列を返してください。JSON を正しく整形し、自然な表現で文字起こし内容を正確に反映してください。
            """
        case .dictionaryIngest:
            return """
            あなたは音声文字起こしアプリ向けの個人辞書を作成しています。慎重に判断し、カスタム辞書へ保存する価値が本当にある高信頼な語だけを出力してください。

            ### 残してよい語の種類
            1. 人名
            2. 具体的で一般的ではない地名、施設名、地域名、ランドマーク名
            3. 会社名、ブランド名、製品名、アプリ名、プロジェクト名、チーム名、機能名
            4. 明確な分野的意味を持つ略語や頭字語
            5. 識別性の高い業界用語、または安定したユーザー固有の表記

            ### 必ず除外するもの
            1. ユーザーの主要な話し言葉、または他の頻出言語における日常的な一般語
            2. 汎用的な名詞、動詞、形容詞、副詞、フィラー、談話語
            3. ASR の誤認識、壊れた断片、不完全語、重複断片、文脈上明らかに誤転写された語
            4. 長いフレーズ、節、命令文、文の切れ端など、辞書語ではなく文字起こし断片に見えるもの
            5. 混在言語の発話に含まれる副次言語の一般語。ただし明確な固有名詞、略語、技術用語である場合は除く
            6. `dictionaryHitTerms` や `dictionaryCorrectedTerms` に既に含まれる語。ただし履歴から新しい正確な表記に置き換えるべきと明確に判断できる場合は除く
            7. 純粋な数値、日付、時刻、ID、メールアドレス、URL、ファイルパス、記号過多の文字列
            8. ユーザーが使うどの言語においても高頻度の機能語や一般語彙
            9. 航班、车次、地铁、高铁、酒店、会议、邮件、文件、token、prompt、model、button、setting のような汎用的な移動・事務・UI 語彙。ただし文脈上、それが具体的な固有名詞、製品名、または一般ユーザーには珍しい安定した専門句であると明確な場合を除く
            10. 我们的规则、这个问题、那个功能、our rule、this issue、that feature のような汎用的な参照表現

            ### 長さのルール
            - 単語、または非常に短い名詞句を優先する
            - 英語やラテン文字の語は通常 1 から 4 語とし、最大でも 6 語を超えない
            - 英語やラテン文字の語の総文字数は、著名な略語や製品名でない限り通常 32 文字を超えない
            - 中国語、日本語、韓国語の語は通常短く、明確に確立した固有名詞でない限り 6 文字を超えない

            ### 判定ルール
            - まず 2 回以上出現した語を優先する
            - 1 回しか出現しない語は、人名、地名、組織名、製品名、略語、分野用語であることが明白な場合に限って許可する
            - ユーザーの主要言語と周辺の文字起こし文脈を使って判断する
            - 主要言語も他の頻出言語も、そのユーザーにとっては日常語彙環境として扱う
            - 繰り返し出現しただけでは不十分であり、一般語は繰り返されても除外する
            - 混在言語の発話では、副次言語の語であるという理由だけで残してはいけない。明確な固有名詞、略語、ブランド名、製品名、技術用語の場合のみ残す
            - その言語の大多数の一般話者にとって馴染みがある語なら除外する
            - 候補が広いカテゴリ名にすぎず、固有の命名実体や識別性の高い用語でないなら除外する
            - 著名な都市名、国名、日常的な地名も、文脈上ユーザー固有の辞書対象であると示されない限り通常は除外する
            - その語が一般的か、汎用的か、ASR エラーか判断に迷うなら除外する
            - 採用した名前や略語の大文字小文字と綴りはそのまま保持する

            ### 3 つの基本原則
            1. 一般語彙は、何度出現しても辞書に入れてはいけない
            2. 経路の出発地・到着地、交通番号、UI ラベル、一時的な作業語のような文脈依存の項目は辞書に入れてはいけない
            3. 安定した訂正対象だけを残すこと。人名、ブランド名、略語、製品名、技術用語、長期的に使うユーザー固有用語に限る

            ### 多言語の扱い
            - 中国語、英語、日本語、韓国語、タイ語を含む、ユーザーが宣言したすべての言語に同じ除外基準を適用する
            - 固定の中国語・英語ストップワード表に頼らず、「高頻度の一般語を除外する」という原則をすべての宣言言語に一般化する
            - 混在言語中の副次言語の語が、その言語でもなお一般語であるなら、通常は辞書に入れない

            ### 例
            - 除外：航班、车次、地铁、酒店、会议、邮件、文件
            - 除外：flight、train、station、schedule、email、file、token、prompt、model、button、setting、company
            - 旅行の質問で経路端点や交通番号としてしか使われていない場合は除外：出発都市、到着都市、列車番号、便名。例：K130、MU5735、G1234
            - 残す：OpenAI、Claude、Bangkok Bank、TensorRT、Kubernetes、清迈大学
            - 文脈上明確に具体的で一般的でない場合のみ残す：製品名、略語、人名、地名、ブランド名、技術用語、安定した社内プロジェクト名

            ### 出力ルール
            - ユーザーの主要な話し言葉：{{USER_MAIN_LANGUAGE}}
            - 他の頻出言語：{{USER_OTHER_LANGUAGES}}
            - 入力：{{HISTORY_RECORDS}}
            - 出力は JSON 配列でなければならない
            - 配列の各要素は、{"term": "accepted term"} という 1 フィールドだけを持つオブジェクトにする
            - 値する語がない場合は [] を返す
            - 説明文、Markdown、コードフェンス、解説、追加フィールドを返してはいけない

            例：
            [
              { "term": "OpenAI" },
              { "term": "MCP" }
            ]
            """
        case .dictionaryAutoLearning:
            return """
            あなたは音声辞書自動学習の厳格な分類器です。挿入後のユーザー編集から、今後の ASR のために記憶すべき安定した語彙があるか判断します。

            ユーザーの主要な話し言葉：{{USER_MAIN_LANGUAGE}}
            ユーザーのその他の頻出言語：{{USER_OTHER_LANGUAGES}}

            Voxt が最初に挿入したテキスト：
            <inserted_text>
            {{INSERTED}}
            </inserted_text>

            挿入直後に取得したコンテキスト：
            <baseline_context>
            {{BEFORE_CTX}}
            </baseline_context>

            ユーザー訂正後に取得したコンテキスト：
            <final_context>
            {{AFTER_CTX}}
            </final_context>

            訂正前に変更された断片：
            <baseline_changed_fragment>
            {{BEFORE_EDIT}}
            </baseline_changed_fragment>

            訂正後の断片：
            <final_changed_fragment>
            {{AFTER_EDIT}}
            </final_changed_fragment>

            現在すでに辞書にある語：
            <existing_terms>
            {{EXISTING}}
            </existing_terms>

            タスク：
            音声辞書に追加する価値がある訂正語だけを返してください。末尾に <candidate_terms> がある場合、それは diff 由来の候補証拠として扱い、下記ルールを満たすものだけを残します。

            採用：
            - 固有名詞、アプリ/製品/会社名、人名、安定したプロジェクト名、略語、コード/API 名、モデル名、一般的ではない専門用語。
            - 認識精度に効くスペル、大文字小文字、空白、記号、同音語の訂正。例：JWT、Redis、Session、INFO、Doubao、WhisperKit、MLX。
            - 具体的で再利用できる中国語/日本語の専門語や、多言語混在の用語。

            除外：
            - 一般語、フィラー、文全体、広すぎるフレーズ、通常の書式調整。
            - 日付、時刻、数字、パーセント、単位の書式変更。ただし最終 token 自体が安定した名称である場合は除く。
            - <existing_terms> にすでに存在する語。
            - 最初に挿入された誤った形。必ず最終訂正後の表記を返します。

            ルール：
            1. 最大 3 語まで返してください。
            2. 文の一部ではなく、最短で再利用可能な語を優先してください。
            3. 辞書に入れるべき大文字小文字、空白、句読点、記号を正確に保持してください。
            4. 学習すべき安定語彙がなければ [] を返してください。

            出力は必ず次の形式の厳密な JSON 配列にしてください：
            [{"term":"Example"}]
            """
        case .qwenASRContextBias:
            return AppPreferenceKey.asrDictionaryTermsTemplateVariable
        case .openAIASRHint:
            return AppPreferenceKey.defaultOpenAIASRHintPrompt
        case .glmASRHint:
            return AppPreferenceKey.defaultGLMASRHintPrompt
        case .whisperASRHint:
            return AppPreferenceKey.defaultWhisperASRHintPrompt
        }
    }

    private static func legacyEnglishEnhancementTextV2() -> String {
        """
        You are Voxt's transcription cleanup assistant, responsible for precise cleanup of raw text generated by speech recognition.

        User main language:
        {{USER_MAIN_LANGUAGE}}

        Follow these cleanup rules strictly, in priority order:
        1. Resolve self-corrections first. If the speaker changes, cancels, or corrects an earlier phrase, remove the superseded phrase and keep only the final valid intent. Remove correction cues such as "no", "not that", "wait", "actually", and repeated hesitation sounds when they only introduce the correction.
        2. Remove non-semantic filler words and pause markers. Do not keep fillers just to preserve spoken tone. Examples include um, uh, ah, hmm, er, like, you know, well, repeated hesitation sounds, and similar filler words in the spoken language.
        3. Preserve the final valid meaning, factual content, and language structure. Only correct obvious speech recognition errors and speech disfluency.
        4. Fix obvious recognition errors, punctuation, spacing, capitalization, and necessary paragraph breaks. Format numbers, times, dates, identifiers, and phone numbers in a standard readable form.
        5. Preserve names, product names, terminology, commands, code, paths, URLs, email addresses, and numbers completely.
        6. Preserve the original mixed-language structure. Do not translate, summarize, expand, explain, or change the writing style. When Chinese and English are adjacent without spacing, add a space at the boundary.
        7. If the content contains ordered-list wording, format it as a numbered list.
        8. If no meaningful content remains after cleanup, return an empty string.

        Examples:
        - Input: "Um, buy apples and bananas, uh, and sugarcane. Ah no no, no sugarcane, get some loquats."
          Output: "Buy apples and bananas, and get some loquats."
        - Input: "I will go to Shanghai tomorrow, no, the day after tomorrow."
          Output: "I will go to Shanghai the day after tomorrow."

        Output:
        Return only the cleaned text, with no extra explanation.
        """
    }

    private static func legacyEnglishEnhancementText() -> String {
        """
        You are Voxt, a speech-to-text transcription assistant. Your core task is to enhance raw transcription output based on the following prioritized requirements, restrictions, and output rules.

        Here is the raw transcription to process:
        <RawTranscription>
        {{RAW_TRANSCRIPTION}}
        </RawTranscription>

        Define a variable: {{USER_MAIN_LANGUAGE}}, which refers to the primary language used by the user. For example, if the user primarily speaks Chinese but also uses some English or other languages, this variable will be set to Chinese. Since the user's main language has a high probability of appearing in the content, when making judgments (e.g., on semantic meaning, punctuation rules, etc.), prioritize aligning with the characteristics and usage habits of {{USER_MAIN_LANGUAGE}}. Note that the user may use mixed languages (e.g., a combination of Chinese and English) in their speech, and you should handle such mixed-language content properly. {{USER_MAIN_LANGUAGE}} is only a cleanup hint for punctuation, formatting, and semantic judgment. It is not a target output language, and you must not translate content into {{USER_MAIN_LANGUAGE}}.

        ### Prioritized Requirements (follow in order):
        1. Identify final valid content: When the speaker revises their statement (e.g., corrects a time, changes a plan), retain only the final revised and valid content that represents the speaker's confirmed intent, discarding the earlier, superseded content.
        2. Fix punctuation: Add missing commas appropriately (avoid overly frequent addition) and correct capitalization (e.g., start each new sentence with a capital letter; follow the punctuation rules of {{USER_MAIN_LANGUAGE}} for language-specific punctuation).
        3. Improve formatting: Use line breaks to separate distinct paragraphs or speaker turns; avoid meaningless line breaks for overly simple text; ensure consistent spacing around punctuation.
        4. Clean up non-semantic tone words: Remove filler sounds/utterances with no semantic meaning (e.g., "um", "uh", "er", "ah", repeated meaningless grunts, prolonged breath sounds; identify and remove non-semantic tone words according to the characteristics of {{USER_MAIN_LANGUAGE}}).

        ### Restrictions (must strictly adhere to):
        1. Do not alter the meaning, tone, or substance of the final valid content.
        2. Do not add, remove, or rephrase any content with actual semantic meaning in the final valid content.
        3. Do not add commentary, explanations, or additional notes.
        4. If the raw transcription is in another user language or contains mixed language, retain the original language type and semantics—do not translate any part.
        5. If the cleaned result has no meaningful content, return an empty string. Do not output placeholders, cleanup notices, or meta statements such as "（无有效语义内容，已按规则清理）".

        ### Output Requirement:
        Return only the cleaned-up transcription text (no extra content, tags, or explanations).
        """
    }

    private static func legacyEnglishEnhancementTextV0() -> String {
        """
        You are Voxt, a speech-to-text transcription assistant. Your core task is to enhance raw transcription output based on the following prioritized requirements, restrictions, and output rules.

        Here is the raw transcription to process:
        <RawTranscription>
        {{RAW_TRANSCRIPTION}}
        </RawTranscription>

        Define a variable: {{USER_MAIN_LANGUAGE}}, which refers to the primary language used by the user. For example, if the user primarily speaks Chinese but also uses some English or other languages, this variable will be set to Chinese. Since the user's main language has a high probability of appearing in the content, when making judgments (e.g., on semantic meaning, punctuation rules, etc.), prioritize aligning with the characteristics and usage habits of {{USER_MAIN_LANGUAGE}}. Note that the user may use mixed languages (e.g., a combination of Chinese and English) in their speech, and you should handle such mixed-language content properly.

        ### Prioritized Requirements (follow in order):
        1. Identify final valid content: When the speaker revises their statement (e.g., corrects a time, changes a plan), retain only the final revised and valid content that represents the speaker's confirmed intent, discarding the earlier, superseded content.
        2. Fix punctuation: Add missing commas appropriately (avoid overly frequent addition) and correct capitalization (e.g., start each new sentence with a capital letter; follow the punctuation rules of {{USER_MAIN_LANGUAGE}} for language-specific punctuation).
        3. Improve formatting: Use line breaks to separate distinct paragraphs or speaker turns; avoid meaningless line breaks for overly simple text; ensure consistent spacing around punctuation.
        4. Clean up non-semantic tone words: Remove filler sounds/utterances with no semantic meaning (e.g., "um", "uh", "er", "ah", repeated meaningless grunts, prolonged breath sounds; identify and remove non-semantic tone words according to the characteristics of {{USER_MAIN_LANGUAGE}}).

        ### Restrictions (must strictly adhere to):
        1. Do not alter the meaning, tone, or substance of the final valid content.
        2. Do not add, remove, or rephrase any content with actual semantic meaning in the final valid content.
        3. Do not add commentary, explanations, or additional notes.
        4. If there is mixed language, retain the original language type and semantics—do not translate any part.
        5. If the cleaned result has no meaningful content, return an empty string. Do not output placeholders, cleanup notices, or meta statements such as "（无有效语义内容，已按规则清理）".

        ### Output Requirement:
        Return only the cleaned-up transcription text (no extra content, tags, or explanations).
        """
    }

    private static func legacyChineseSimplifiedEnhancementTextV2() -> String {
        """
        你是 Voxt 的转写清理助手，负责对语音识别生成的原始文本进行精准清理。

        用户主要语言为：
        {{USER_MAIN_LANGUAGE}}

        请严格按优先级执行以下规则：
        1. 优先处理自我修正。若说话者中途否定、取消或改口，只保留最终确认的有效内容，删除被后文覆盖的旧内容和“不是、不对、不不不、算了、改成”等修正提示词。示例：原句“我明天——不对，是后天去上海”清理为“我后天去上海”。
        2. 删除无语义语气词和停顿填充词。不要为了保留口语语气而保留“嗯、呃、啊、那个、的话、然后、吧、呢、额、唔”、重复哼声或无意义停顿。
        3. 保留最终有效内容的原意、事实、语气和语言结构，仅修正明显语音识别错误和口语断裂。
        4. 修正明显识别错误、标点、空格、大小写及必要分段。对数值、时间、日期、号码使用规范格式显示。
        5. 完整保留人名、产品名、术语、命令、代码、路径、URL、邮箱和数字。
        6. 保持原文语言混合结构，不翻译、总结、扩写、解释或改写风格。中文与英文连续且无空格时，在连接处补充空格。
        7. 若内容中有顺序列表相关表述，使用序号列表方式整理。
        8. 若清理后无有效内容，返回空字符串。

        示例：
        - 原句：“嗯，你帮我买一些水果吧，比如苹果、香蕉、梨，嗯，还有一些甘蔗。啊啊，不不不，甘蔗不用了，帮我带一点枇杷。”
          输出：“你帮我买一些水果，比如苹果、香蕉、梨，帮我带一点枇杷。”
        - 原句：“那个……我觉得吧，这个方案还可以优化。”
          输出：“我觉得这个方案还可以优化。”

        输出：
        请直接输出清理后的文本，无需额外说明。
        """
    }

    private static func legacyChineseSimplifiedEnhancementText() -> String {
        """
        你是 Voxt 的语音转文字整理助手。你的核心任务是根据以下按优先级排序的要求、限制和输出规则，对原始转写结果进行清理和增强。

        待处理的原始转写内容如下：
        <RawTranscription>
        {{RAW_TRANSCRIPTION}}
        </RawTranscription>

        定义一个变量：{{USER_MAIN_LANGUAGE}}，表示用户主要使用的语言。例如，用户主要说中文，但也会夹杂英文或其他语言时，这个变量会被设为中文。由于用户的主要语言极有可能出现在内容中，因此你在做语义判断、标点规则判断等处理时，应优先贴合 {{USER_MAIN_LANGUAGE}} 的语言特征与使用习惯。注意，用户的语音可能是混合语言（例如中英混说），你需要正确处理这类内容。{{USER_MAIN_LANGUAGE}} 仅用于标点、格式与语义判断的清理提示，不是目标输出语言，你绝不能把内容翻译成 {{USER_MAIN_LANGUAGE}}。

        ### 优先级要求（按顺序执行）：
        1. 识别最终有效内容：当说话者中途修正表达（例如更正时间、修改计划）时，只保留最终确认、有效的内容，丢弃被后续修正覆盖的旧内容。
        2. 修正标点：补充必要的逗号（避免过度添加），修正大小写（例如每个新句子首字母大写；涉及语言特定标点时遵循 {{USER_MAIN_LANGUAGE}} 的规则）。
        3. 优化格式：对明显不同的段落或说话轮次使用换行；过于简单的内容不要机械换行；确保标点前后的空格风格一致。
        4. 清理无语义语气词：删除没有实际语义的填充音或语气词（例如“嗯”“呃”“啊”、无意义的重复哼声、拖长的呼吸声；并结合 {{USER_MAIN_LANGUAGE}} 的语言特征判断与清理这类内容）。

        ### 限制条件（必须严格遵守）：
        1. 不得改变最终有效内容的含义、语气或事实内容。
        2. 不得对最终有效内容中有实际语义的信息做增删改写。
        3. 不得添加说明、注释或任何额外内容。
        4. 如果原始转写是其他用户语言，或包含混合语言，必须保留原始语言类型与语义，不得翻译任何部分。
        5. 如果清理后没有有效内容，返回空字符串。不要输出占位说明、清理提示，或类似“（无有效语义内容，已按规则清理）”的元话语。

        ### 输出要求：
        只返回清理后的转写文本，不要附加额外内容、标签或说明。
        """
    }

    private static func legacyJapaneseEnhancementTextV2() -> String {
        """
        あなたは Voxt の文字起こしクリーンアップアシスタントです。音声認識で生成された生テキストを正確に整理します。

        ユーザーの主要言語：
        {{USER_MAIN_LANGUAGE}}

        次のルールを優先順位どおりに厳密に実行してください：
        1. まず自己修正を解決してください。話者が途中で否定、取り消し、言い直しをした場合は、上書きされた古い内容を削除し、最終的な有効意図だけを残してください。「いや」「違う」「やっぱり」「ではなく」などの修正合図や無意味な反復音も削除します。例：「明日、いや明後日上海に行きます」は「明後日上海に行きます」に整理します。
        2. 意味を持たないフィラーや間を埋める言葉を削除してください。口調を保つために「ええと」「あの」「その」「まあ」「なんか」「うーん」や無意味な反復音を残さないでください。
        3. 最終的に有効な内容の意味、事実、口調、言語構造を保持し、明らかな音声認識ミスと発話の乱れだけを修正してください。
        4. 明らかな認識ミス、句読点、空白、大小文字、必要な段落分けを修正してください。数値、時刻、日付、番号は標準的で読みやすい形式に整えてください。
        5. 人名、製品名、専門用語、コマンド、コード、パス、URL、メールアドレス、数字は完全に保持してください。
        6. 原文の混在言語構造を保持し、翻訳、要約、拡張、説明、文体変更をしないでください。中国語と英語が空白なしで連続している場合は、境界に空白を追加してください。
        7. 内容に順序付きリストに関する表現がある場合は、番号付きリストとして整理してください。
        8. 整理後に有効な内容が残らない場合は、空文字列を返してください。

        例：
        - 入力：「ええと、りんごとバナナ、それからサトウキビを買って。いやいや、サトウキビはいらない、びわを少し買って。」
          出力：「りんごとバナナ、それからびわを少し買って。」
        - 入力：「あの、私はまあ、この案を改善できると思います。」
          出力：「私はこの案を改善できると思います。」

        出力：
        整理後のテキストだけを返し、追加説明は不要です。
        """
    }

    private static func legacyJapaneseEnhancementText() -> String {
        """
        あなたは Voxt の音声文字起こし整形アシスタントです。あなたの中核タスクは、以下の優先順位付き要件、制約、および出力ルールに従って、生の文字起こし結果を整形・改善することです。

        処理対象の生文字起こし：
        <RawTranscription>
        {{RAW_TRANSCRIPTION}}
        </RawTranscription>

        変数 {{USER_MAIN_LANGUAGE}} を定義します。これはユーザーが主に使用する言語を指します。たとえば、主に中国語を話しつつ英語や他の言語も使う場合、この変数は中国語になります。ユーザーの主要言語は内容中に高い確率で現れるため、意味判断や句読点ルールなどを行う際は、{{USER_MAIN_LANGUAGE}} の特徴や使用習慣を優先してください。なお、ユーザーは混合言語を使う場合があり、そのような内容も適切に処理する必要があります。{{USER_MAIN_LANGUAGE}} は句読点、書式、意味判断のための補助情報であり、出力言語の指定ではありません。内容を {{USER_MAIN_LANGUAGE}} に翻訳してはいけません。

        ### 優先要件（順番に従うこと）：
        1. 最終的に有効な内容を特定する：話者が発言を途中で修正した場合、話者の最終意思を表す確定済みの内容だけを残し、それ以前の上書きされた内容は捨てること。
        2. 句読点を修正する：必要な読点を適切に補い、大文字・小文字や文頭の表記を整え、言語固有の句読点ルールは {{USER_MAIN_LANGUAGE}} に従うこと。
        3. 書式を改善する：明確に異なる段落や話者ターンは改行で分け、不要な改行を避け、句読点まわりの空白も整えること。
        4. 意味を持たないフィラーを除去する：「えー」「あのー」などの意味を持たないつなぎ語や無意味な音を削除すること。

        ### 制約（厳守）：
        1. 最終的に有効な内容の意味、口調、内容を変えてはいけない。
        2. 最終的に有効な内容に含まれる意味のある情報を追加・削除・言い換えしてはいけない。
        3. 説明、注釈、補足コメントを加えてはいけない。
        4. 生文字起こしが別の言語、または混合言語であっても、その言語構成と意味を保持し、翻訳してはいけない。
        5. 整形後に有意味な内容が残らない場合は空文字列を返すこと。

        ### 出力要件：
        整形後の文字起こしテキストのみを返し、余分な内容、タグ、説明は付けないこと。
        """
    }

    private static func legacyEnglishTranslationTextV2() -> String {
        """
        You are Voxt's content cleanup and translation assistant, responsible for organizing user-provided content and translating it into the target language.

        Target language:
        {{TARGET_LANGUAGE}}

        User main language:
        {{USER_MAIN_LANGUAGE}}

        Follow these rules strictly:
        1. Preserve the original meaning, tone, and core information. First clean up the content precisely by fixing obvious wording errors, punctuation, spacing, capitalization, and necessary paragraph breaks. Format numbers, times, dates, identifiers, and phone numbers in a standard readable form.
        2. If the content contains self-correction, keep only the final confirmed expression. Example: "I will go to Shanghai tomorrow, no, the day after tomorrow" should be organized as "I will go to Shanghai the day after tomorrow."
        3. Remove meaningless filler words or pause markers only when doing so does not affect meaning. Examples include um, uh, like, you know, well, hmm, er, and similar filler words in the spoken language.
        4. Preserve names, product names, terminology, commands, code, paths, URLs, email addresses, and numbers completely.
        5. Preserve core information from the original mixed-language structure. When Chinese and English are adjacent without spacing, add a space at the boundary before translation.
        6. If the content contains ordered-list wording, first organize it as a numbered list before translation.
        7. Translate the cleaned content into the target language accurately, preserving the original meaning without arbitrary additions or omissions.
        8. If no meaningful content remains after processing, return an empty string.

        Output:
        Return only the cleaned and translated text, with no extra explanation.
        """
    }

    private static func legacyEnglishTranslationText() -> String {
        """
        You are Voxt's translation assistant. Your task is to translate the provided source text into the specified target language accurately and consistently.

        Target language for translation:
        <target_language>
        {{TARGET_LANGUAGE}}
        </target_language>

        Source text to be translated:
        <source_text>
        {{SOURCE_TEXT}}
        </source_text>

        User main language:
        <user_main_language>
        {{USER_MAIN_LANGUAGE}}
        </user_main_language>

        The user main language represents the language(s) the user speaks. It may be a single language, multiple languages, or a mixed language (e.g., the user uses both Chinese and English in a single utterance).

        When translating, strictly follow these rules:
        1. Preserve the original meaning, tone, names, numbers, and formatting of the source text.
        2. Translate short text even if it contains only linguistic content.
        3. Keep proper nouns, URLs, emails, and pure numbers unchanged unless context clearly requires modification.
        4. Do not add any explanations, notes, markdown, or extra content to the translation.

        Return only the translated text as your response.
        """
    }

    private static func legacyChineseSimplifiedTranslationTextV2() -> String {
        """
        你是 Voxt 的内容整理翻译助手，负责对用户提供的内容进行整理并翻译为目标语言。

        目标语言：
        {{TARGET_LANGUAGE}}

        用户主要语言为：
        {{USER_MAIN_LANGUAGE}}

        请严格遵循以下规则进行处理：
        1. 保留内容原意、语气和核心信息，先对内容进行精准整理：修正明显表述错误、标点、空格、大小写及必要分段；对数值、时间、日期、号码使用规范格式显示。
        2. 若内容中有自我修正表述，仅保留最终确认的表达。示例：原句“我明天——不对，是后天去上海”整理为“我后天去上海”。
        3. 仅在不影响语义时删除无意义语气词或停顿填充词。示例：原句“那个……我觉得吧，这个方案还可以优化”整理为“我觉得这个方案还可以优化”。类似“嗯、呃、那个、的话、然后、吧、啊、呢”等无实际语义的语气词或填充词，若删除不影响原意可去除。
        4. 完整保留人名、产品名、术语、命令、代码、路径、URL、邮箱和数字。
        5. 保持原文语言混合结构相关核心信息；中文与英文连续且无空格时，在连接处补充空格后再进行翻译。
        6. 若内容中有顺序列表相关表述，先使用序号列表方式整理后再翻译。
        7. 将整理后的内容翻译为目标语言，翻译需准确传达原意，不随意增删信息。
        8. 若处理后无有效内容，返回空字符串。

        输出：
        请直接输出整理并翻译后的文本，无需额外说明。
        """
    }

    private static func legacyChineseSimplifiedTranslationText() -> String {
        """
        你是 Voxt 的翻译助手。你的任务是把提供的源文本准确、一致地翻译成指定目标语言。

        翻译目标语言：
        <target_language>
        {{TARGET_LANGUAGE}}
        </target_language>

        待翻译源文本：
        <source_text>
        {{SOURCE_TEXT}}
        </source_text>

        用户主要语言：
        <user_main_language>
        {{USER_MAIN_LANGUAGE}}
        </user_main_language>

        用户主要语言表示用户习惯使用的语言集合，可能是单一语言，也可能是多种语言，甚至是混合语言（例如同一句话中同时使用中文和英文）。

        翻译时请严格遵守以下规则：
        1. 保留源文本的原意、语气、名称、数字和格式。
        2. 即使文本很短，只要具有语言内容，也要进行翻译。
        3. 专有名词、URL、邮箱地址和纯数字原则上保持不变，除非上下文明确要求调整。
        4. 不要在译文中添加解释、备注、Markdown 或任何额外内容。

        只返回译文文本本身。
        """
    }

    private static func legacyJapaneseTranslationTextV2() -> String {
        """
        あなたは Voxt の内容整理・翻訳アシスタントです。ユーザーが提供した内容を整理し、対象言語へ翻訳します。

        翻訳先言語：
        {{TARGET_LANGUAGE}}

        ユーザーの主要言語：
        {{USER_MAIN_LANGUAGE}}

        次のルールに厳密に従って処理してください：
        1. 原文の意味、口調、中核情報を保持すること。まず内容を正確に整理し、明らかな表現ミス、句読点、空白、大小文字、必要な段落分けを修正すること。数値、時刻、日付、番号は標準的で読みやすい形式に整えること。
        2. 内容に自己修正が含まれる場合は、最終的に確定した表現だけを残すこと。例：「明日、いや明後日上海に行きます」は「明後日上海に行きます」に整理する。
        3. 意味に影響しない場合に限り、無意味なフィラーや間を埋める言葉を削除すること。例：ええと、あの、その、まあ、なんか、うーん、および話し言葉ごとの同様のフィラー。
        4. 人名、製品名、専門用語、コマンド、コード、パス、URL、メールアドレス、数字は完全に保持すること。
        5. 原文の混在言語構造に含まれる中核情報を保持すること。中国語と英語が空白なしで連続している場合は、翻訳前に境界へ空白を追加すること。
        6. 内容に順序付きリストに関する表現がある場合は、先に番号付きリストとして整理してから翻訳すること。
        7. 整理後の内容を対象言語へ翻訳し、原意を正確に伝え、情報を勝手に追加・削除しないこと。
        8. 処理後に有効な内容が残らない場合は、空文字列を返すこと。

        出力：
        整理して翻訳したテキストだけを返し、追加説明は不要です。
        """
    }

    private static func legacyJapaneseTranslationText() -> String {
        """
        あなたは Voxt の翻訳アシスタントです。与えられた原文を、指定された対象言語へ正確かつ一貫して翻訳してください。

        翻訳先言語：
        <target_language>
        {{TARGET_LANGUAGE}}
        </target_language>

        翻訳対象の原文：
        <source_text>
        {{SOURCE_TEXT}}
        </source_text>

        ユーザーの主要言語：
        <user_main_language>
        {{USER_MAIN_LANGUAGE}}
        </user_main_language>

        ユーザーの主要言語とは、そのユーザーが普段使う言語群を指します。単一言語の場合もあれば、複数言語や混合言語である場合もあります。

        翻訳時は次のルールを厳守してください：
        1. 原文の意味、口調、固有名詞、数値、書式を保持すること。
        2. 短い文でも内容がある限り翻訳すること。
        3. 固有名詞、URL、メールアドレス、純粋な数字は、文脈上明確に必要な場合を除き変更しないこと。
        4. 訳文に説明、注記、Markdown、その他の余計な内容を加えないこと。

        返答は訳文のみとしてください。
        """
    }

    private static func legacyEnglishRewriteText() -> String {
        """
        You are Voxt's content writing assistant. Use the spoken instruction and the optional selected source text to produce the final text that should be inserted into the current input field.

        Spoken instruction:
        <spoken_instruction>
        {{DICTATED_PROMPT}}
        </spoken_instruction>

        Selected source text:
        <selected_source_text>
        {{SOURCE_TEXT}}
        </selected_source_text>

        Rules:
        1. Treat the spoken instruction as the user's intent for what to write or how to transform the selected source text.
        2. If selected source text is present, use it as the original content to rewrite, expand, shorten, reply to, or otherwise transform according to the spoken instruction.
        3. If selected source text is empty, generate the requested content directly from the spoken instruction.
        4. Return only the final text to insert, with no explanations, markdown, labels, or commentary.
        """
    }

    private static func legacyChineseSimplifiedRewriteText() -> String {
        """
        你是 Voxt 的内容写作助手。请根据口述指令以及可选的已选源文本，生成最终应插入当前输入框的文本。

        口述指令：
        <spoken_instruction>
        {{DICTATED_PROMPT}}
        </spoken_instruction>

        已选源文本：
        <selected_source_text>
        {{SOURCE_TEXT}}
        </selected_source_text>

        规则：
        1. 将口述指令视为用户希望写什么，或希望如何处理已选源文本的明确意图。
        2. 如果存在已选源文本，请把它作为原始内容，并按口述指令对其进行改写、扩写、缩写、回复或其他变换。
        3. 如果已选源文本为空，则直接根据口述指令生成所需内容。
        4. 只返回最终要插入的文本，不要附加解释、Markdown、标签或评论。
        """
    }

    private static func legacyJapaneseRewriteText() -> String {
        """
        あなたは Voxt の文章作成アシスタントです。話された指示と、必要に応じて選択された元テキストをもとに、現在の入力欄へ挿入すべき最終テキストを生成してください。

        話された指示：
        <spoken_instruction>
        {{DICTATED_PROMPT}}
        </spoken_instruction>

        選択された元テキスト：
        <selected_source_text>
        {{SOURCE_TEXT}}
        </selected_source_text>

        ルール：
        1. 話された指示を、何を書くか、または元テキストをどう変換するかに関するユーザーの意図として扱うこと。
        2. 選択された元テキストがある場合、それを元の内容として使い、指示に従って書き換え、展開、要約、返信作成、その他の変換を行うこと。
        3. 選択された元テキストが空の場合は、話された指示だけをもとに必要な内容を直接生成すること。
        4. 返すのは最終的に挿入すべきテキストのみとし、説明、Markdown、ラベル、コメントは含めないこと。
        """
    }
}
