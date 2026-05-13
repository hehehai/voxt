import SwiftUI
import Foundation

struct RemoteProviderConfigurationSheet: View {
    @Environment(\.dismiss) var dismiss
    @AppStorage(AppPreferenceKey.remoteASRSelectedProvider) var selectedRemoteASRProviderRaw = RemoteASRProvider.openAIWhisper.rawValue
    @AppStorage(AppPreferenceKey.remoteLLMSelectedProvider) var selectedRemoteLLMProviderRaw = RemoteLLMProvider.openAI.rawValue

    let providerTitle: String
    let credentialHint: String?
    let showsDoubaoFields: Bool
    let testTarget: RemoteProviderTestTarget
    let configuration: RemoteProviderConfiguration
    let onSave: (RemoteProviderConfiguration) -> Void

    @State var selectedProviderModel = ""
    @State var customModelID = ""
    @State var endpoint = ""
    @State var apiKey = ""
    @State var appID = ""
    @State var accessToken = ""
    @State var searchEnabled = false
    @State var openAIChunkPseudoRealtimeEnabled = false
    @State var openAIReasoningEffort = OpenAIReasoningEffort.automatic.rawValue
    @State var openAITextVerbosity = OpenAITextVerbosity.automatic.rawValue
    @State var openAIMaxOutputTokensText = ""
    @State var doubaoDictionaryMode = DoubaoDictionaryMode.requestScoped.rawValue
    @State var doubaoEnableRequestHotwords = true
    @State var doubaoEnableRequestCorrections = true
    @State var ollamaResponseFormat = OllamaResponseFormat.plain.rawValue
    @State var ollamaJSONSchema = ""
    @State var ollamaThinkMode = OllamaThinkMode.off.rawValue
    @State var ollamaKeepAlive = ""
    @State var ollamaLogprobsEnabled = false
    @State var ollamaTopLogprobsText = ""
    @State var ollamaOptionsJSON = ""
    @State var omlxResponseFormat = OMLXResponseFormat.plain.rawValue
    @State var omlxJSONSchema = ""
    @State var omlxIncludeUsageStreamOptions = false
    @State var omlxExtraBodyJSON = ""
    @State var isTestingConnection = false
    @State var testResultMessage: String?
    @State var testResultIsSuccess = false

    private var dialogWidth: CGFloat {
        showsLargeAdvancedProviderSection ? 520 : 440
    }

    private var dialogMaxHeight: CGFloat {
        showsLargeAdvancedProviderSection ? 720 : 560
    }

    private var scrollContentMaxHeight: CGFloat {
        showsLargeAdvancedProviderSection ? 600 : 440
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(AppLocalization.format("Configure %@", providerTitle))
                .font(.title3.weight(.semibold))

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    modelSection

                    if !isDoubaoASRTest {
                        endpointAndKeySection
                    }

                    if showsSearchSection {
                        searchSection
                    }

                    if isOpenAILLMProvider {
                        openAILLMConfigurationSection
                    }

                    if isOllamaLLMProvider {
                        ollamaConfigurationSection
                    }

                    if isOMLXLLMProvider {
                        omlxConfigurationSection
                    }

                    if showsDoubaoFields {
                        doubaoCredentialsSection
                        doubaoDictionarySection
                    }

                    if isOpenAIASRTest {
                        openAIChunkSection
                    }

                    if let credentialHint, !credentialHint.isEmpty {
                        Text(credentialHint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let activeProviderNotice {
                        Text(activeProviderNotice)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.trailing, 4)
            }
            .frame(maxHeight: scrollContentMaxHeight)

            actionSection

            if let testResultMessage, !testResultMessage.isEmpty {
                Text(testResultMessage)
                    .font(.caption)
                    .foregroundStyle(testResultIsSuccess ? .green : .orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .frame(width: dialogWidth)
        .frame(maxHeight: dialogMaxHeight, alignment: .top)
        .onAppear {
            configureModelSelection()
            customModelID = configuration.model
            endpoint = configuration.endpoint
            apiKey = configuration.apiKey
            appID = configuration.appID
            accessToken = configuration.accessToken
            searchEnabled = configuration.searchEnabled
            openAIChunkPseudoRealtimeEnabled = configuration.openAIChunkPseudoRealtimeEnabled
            openAIReasoningEffort = configuration.openAIReasoningEffort
            openAITextVerbosity = configuration.openAITextVerbosity
            openAIMaxOutputTokensText = configuration.openAIMaxOutputTokens.map(String.init) ?? ""
            doubaoDictionaryMode = configuration.doubaoDictionaryMode
            doubaoEnableRequestHotwords = configuration.doubaoEnableRequestHotwords
            doubaoEnableRequestCorrections = configuration.doubaoEnableRequestCorrections
            ollamaResponseFormat = configuration.ollamaResponseFormat
            ollamaJSONSchema = configuration.ollamaJSONSchema
            ollamaThinkMode = configuration.ollamaThinkMode
            ollamaKeepAlive = configuration.ollamaKeepAlive
            ollamaLogprobsEnabled = configuration.ollamaLogprobsEnabled
            ollamaTopLogprobsText = configuration.ollamaTopLogprobs.map(String.init) ?? ""
            ollamaOptionsJSON = configuration.ollamaOptionsJSON
            omlxResponseFormat = configuration.omlxResponseFormat
            omlxJSONSchema = configuration.omlxJSONSchema
            omlxIncludeUsageStreamOptions = configuration.omlxIncludeUsageStreamOptions
            omlxExtraBodyJSON = configuration.omlxExtraBodyJSON
        }
    }
}
