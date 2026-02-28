import SwiftUI

struct SettingsView: View {
    @ObservedObject var mlxModelManager: MLXModelManager
    @ObservedObject var customLLMManager: CustomLLMModelManager
    @ObservedObject var historyStore: TranscriptionHistoryStore
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))

            HStack(alignment: .top, spacing: 8) {
                SettingsSidebar(selectedTab: $selectedTab)
                    .frame(width: 170)
                    .frame(maxHeight: .infinity, alignment: .top)

                VStack(alignment: .leading, spacing: 12) {
                    Text(selectedTab.title)
                        .font(.title3.weight(.semibold))
                        .padding(.horizontal, 8)

                    if selectedTab == .history {
                        HistorySettingsView(historyStore: historyStore)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .padding(.horizontal, 8)
                            .padding(.top, 2)
                            .padding(.bottom, 12)
                    } else {
                        ScrollView {
                            Group {
                                switch selectedTab {
                                case .general:
                                    GeneralSettingsView()
                                case .permissions:
                                    PermissionsSettingsView()
                                case .model:
                                    ModelSettingsView(
                                        mlxModelManager: mlxModelManager,
                                        customLLMManager: customLLMManager
                                    )
                                case .hotkey:
                                    HotkeySettingsView()
                                case .about:
                                    AboutSettingsView()
                                case .history:
                                    EmptyView()
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(.horizontal, 8)
                            .padding(.top, 2)
                            .padding(.bottom, 12)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
            .padding(.top, 10)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .frame(minWidth: 760, minHeight: 560)
        .ignoresSafeArea(.container, edges: .top)
    }
}

private struct SettingsSidebar: View {
    @Binding var selectedTab: SettingsTab

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(SettingsTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: tab.iconName)
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 16)
                        Text(tab.title)
                            .font(.system(size: 13, weight: .medium))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(tab == selectedTab ? .white : .primary)
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(tab == selectedTab ? Color.accentColor : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
        .padding(.top, 34)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.10), radius: 10, x: 0, y: 3)
    }
}
