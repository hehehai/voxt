import SwiftUI
import AppKit

struct AppEnhancementSettingsView: View {
    @AppStorage(AppPreferenceKey.interfaceLanguage) var interfaceLanguageRaw = AppInterfaceLanguage.system.rawValue

    @State var apps: [BranchApp] = []
    @State var urlItems: [BranchURLItem] = []
    @State var groups: [AppBranchGroup] = []

    @State var sourceTab: SourceTab = .apps
    @State var draggingAppID: String?
    @State var hoveredCardID: String?

    @State var modal: AppBranchModal?
    @State var groupNameDraft = ""
    @State var groupPromptDraft = ""
    @State var urlDraft = ""
    @State var modalErrorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            sourceListCard
            groupListCard
        }
        .onAppear(perform: handleOnAppear)
        .onReceive(NotificationCenter.default.publisher(for: NSWorkspace.didActivateApplicationNotification)) { _ in
            refreshApps()
        }
        .onChange(of: groups) { _, _ in
            saveGroups()
        }
        .onChange(of: urlItems) { _, _ in
            saveURLs()
        }
        .sheet(item: $modal) { currentModal in
            modalView(for: currentModal)
        }
        .id(interfaceLanguageRaw)
    }
}
