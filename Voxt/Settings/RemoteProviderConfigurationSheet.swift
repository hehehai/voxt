import SwiftUI
import Foundation

struct RemoteProviderConfigurationSheet: View {
    @Environment(\.dismiss) var dismiss
    @AppStorage(AppPreferenceKey.remoteASRSelectedProvider) var selectedRemoteASRProviderRaw = RemoteASRProvider.openAIWhisper.rawValue

    let providerTitle: String
    let credentialHint: String?
    let showsDoubaoFields: Bool
    let testTarget: RemoteProviderTestTarget
    let configuration: RemoteProviderConfiguration
    let onSave: (RemoteProviderConfiguration) -> Void

    @State var selectedProviderModel = ""
    @State var customModelID = ""
    @State var selectedMeetingModel = ""
    @State var customMeetingModelID = ""
    @State var endpoint = ""
    @State var apiKey = ""
    @State var appID = ""
    @State var accessToken = ""
    @State var openAIChunkPseudoRealtimeEnabled = false
    @State var doubaoDictionaryMode = DoubaoDictionaryMode.requestScoped.rawValue
    @State var doubaoEnableRequestHotwords = true
    @State var doubaoEnableRequestCorrections = true
    @State var isTestingConnection = false
    @State var testResultMessage: String?
    @State var testResultIsSuccess = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(AppLocalization.format("Configure %@", providerTitle))
                .font(.title3.weight(.semibold))

            modelSection

            if showsMeetingASRSection {
                meetingModelSection
            }

            if !isDoubaoASRTest {
                endpointAndKeySection
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

            actionSection

            if let testResultMessage, !testResultMessage.isEmpty {
                Text(testResultMessage)
                    .font(.caption)
                    .foregroundStyle(testResultIsSuccess ? .green : .orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .frame(width: 440)
        .onAppear {
            configureModelSelection()
            customModelID = configuration.model
            configureMeetingModelSelection()
            customMeetingModelID = configuration.meetingModel
            endpoint = configuration.endpoint
            apiKey = configuration.apiKey
            appID = configuration.appID
            accessToken = configuration.accessToken
            openAIChunkPseudoRealtimeEnabled = configuration.openAIChunkPseudoRealtimeEnabled
            doubaoDictionaryMode = configuration.doubaoDictionaryMode
            doubaoEnableRequestHotwords = configuration.doubaoEnableRequestHotwords
            doubaoEnableRequestCorrections = configuration.doubaoEnableRequestCorrections
        }
    }
}
