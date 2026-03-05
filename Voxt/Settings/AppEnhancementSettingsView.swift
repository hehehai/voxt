import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct AppEnhancementSettingsView: View {
    @AppStorage(AppPreferenceKey.interfaceLanguage) private var interfaceLanguageRaw = AppInterfaceLanguage.system.rawValue
    @State private var apps: [BranchApp] = []
    @State private var urlItems: [BranchURLItem] = []
    @State private var groups: [AppBranchGroup] = []

    @State private var sourceTab: SourceTab = .apps
    @State private var draggingAppID: String?
    @State private var hoveredCardID: String?

    @State private var modal: AppBranchModal?
    @State private var groupNameDraft = ""
    @State private var groupPromptDraft = ""
    @State private var urlDraft = ""
    @State private var modalErrorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            sourceListCard
            groupListCard
        }
        .onAppear {
            loadPersistedGroups()
            loadPersistedURLs()
            refreshApps()
        }
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

    private var sourceListCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    sourceTabs

                    Spacer()

                    if sourceTab == .apps {
                        Text(AppLocalization.localizedString("Tip: Drag resources into groups below."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if sourceTab == .urls {
                        Button(AppLocalization.localizedString("Add")) {
                            urlDraft = ""
                            modalErrorMessage = nil
                            modal = .addURLs
                        }
                    }
                }

                switch sourceTab {
                case .apps:
                    appsGrid
                case .urls:
                    urlsList
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }

    private var sourceTabs: some View {
        HStack(spacing: 2) {
            ForEach(SourceTab.allCases) { tab in
                Button {
                    sourceTab = tab
                } label: {
                    Text(tab.title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(sourceTab == tab ? Color.accentColor : Color.secondary)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(sourceTab == tab ? Color.accentColor.opacity(0.14) : .clear)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(sourceTab == tab ? Color.accentColor.opacity(0.45) : .clear, lineWidth: 1)
                }
            }
        }
        .padding(2)
        .frame(width: 154)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private var appsGrid: some View {
        GeometryReader { proxy in
            let columns = appGridColumns(for: proxy.size.width)
            ScrollView(.vertical) {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                    ForEach(apps) { app in
                        appCard(
                            for: app,
                            showsGroupBadge: true,
                            supportsHoverBadge: true,
                            hoverCardID: "top:\(app.id)"
                        )
                        .onDrag {
                            draggingAppID = app.id
                            return NSItemProvider(object: "app:\(app.id)" as NSString)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(height: 180)
    }

    private var urlsList: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 8) {
                ForEach(urlItems) { item in
                    urlRow(item)
                        .onDrag {
                            NSItemProvider(object: "url:\(item.id.uuidString)" as NSString)
                        }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 180)
    }

    private func urlRow(_ item: BranchURLItem) -> some View {
        let group = groupForURL(id: item.id)

        return HStack(spacing: 10) {
            Image(systemName: "globe")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            Text(item.pattern)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            if let group {
                HStack(spacing: 4) {
                    Text(group.name)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Button {
                        removeURLFromGroup(urlID: item.id)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.accentColor))
                .frame(maxWidth: 56, alignment: .trailing)
            }

            Button(AppLocalization.localizedString("Edit")) {
                urlDraft = item.pattern
                modalErrorMessage = nil
                modal = .editURL(item.id)
            }
            .controlSize(.small)

            Button(AppLocalization.localizedString("Delete")) {
                deleteURLItem(id: item.id)
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private var groupListCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(groupsTitle)
                        .font(.headline)
                    Spacer()
                    Button(AppLocalization.localizedString("Create Group")) {
                        groupNameDraft = ""
                        groupPromptDraft = ""
                        modalErrorMessage = nil
                        modal = .createGroup
                    }
                }

                if groups.isEmpty {
                    Text(AppLocalization.localizedString("No groups yet. Create a group, then drag apps or URLs into it."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 10) {
                            ForEach(groups) { group in
                                groupCard(for: group)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 224)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }

    private func appCard(
        for app: BranchApp,
        showsGroupBadge: Bool,
        supportsHoverBadge: Bool,
        hoverCardID: String,
        isOffline: Bool = false,
        removeAction: (() -> Void)? = nil
    ) -> some View {
        let group = groupForApp(bundleID: app.id)
        let isDragging = draggingAppID == app.id
        let isHovering = hoveredCardID == hoverCardID
        let isAssigned = group != nil

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(nsImage: app.icon)
                    .resizable()
                    .frame(width: 24, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text(app.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 46, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isDragging
                        ? Color.accentColor
                        : (isOffline
                            ? Color.primary.opacity(0.18)
                            : (isAssigned ? Color.accentColor.opacity(0.55) : Color.primary.opacity(0.10))),
                    lineWidth: isDragging ? 1.5 : 1
                )
        }
        .contentShape(Rectangle())
        .overlay(alignment: .topTrailing) {
            if showsGroupBadge, let group, isHovering {
                HStack(spacing: 4) {
                    Text(group.name)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Button {
                        removeAppFromGroup(bundleID: app.id)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.accentColor))
                .frame(maxWidth: 56, alignment: .trailing)
                .padding(6)
            } else if let removeAction, isHovering {
                Button(action: removeAction) {
                    Image(systemName: "trash")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.accentColor))
                }
                .buttonStyle(.plain)
                .padding(6)
            }
        }
        .onHover { hovering in
            guard supportsHoverBadge else { return }
            if hovering {
                hoveredCardID = hoverCardID
            } else if hoveredCardID == hoverCardID {
                hoveredCardID = nil
            }
        }
    }

    private func urlCard(
        for item: BranchURLItem,
        hoverCardID: String,
        removeAction: @escaping () -> Void
    ) -> some View {
        let isHovering = hoveredCardID == hoverCardID

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "globe")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                Text(item.pattern)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 46, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.55), lineWidth: 1)
        }
        .contentShape(Rectangle())
        .overlay(alignment: .topTrailing) {
            if isHovering {
                Button(action: removeAction) {
                    Image(systemName: "trash")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.accentColor))
                }
                .buttonStyle(.plain)
                .padding(6)
            }
        }
        .onTapGesture(count: 2) {
            modal = .urlDetail(item)
        }
        .onHover { hovering in
            if hovering {
                hoveredCardID = hoverCardID
            } else if hoveredCardID == hoverCardID {
                hoveredCardID = nil
            }
        }
    }

    private func groupCard(for group: AppBranchGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            let members = groupMembers(group: group)
            HStack(spacing: 8) {
                Button {
                    setGroupExpanded(groupID: group.id, expanded: !group.isExpanded)
                } label: {
                    Image(systemName: group.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.plain)

                Text(group.name)
                    .font(.system(size: 13, weight: .semibold))

                Text(AppLocalization.format("%d items", members.count))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                Spacer()

                Button(AppLocalization.localizedString("Edit")) {
                    groupNameDraft = group.name
                    groupPromptDraft = group.prompt
                    modalErrorMessage = nil
                    modal = .editGroup(group.id)
                }
                .controlSize(.small)

                Button(AppLocalization.localizedString("Delete")) {
                    deleteGroup(groupID: group.id)
                }
                .controlSize(.small)
            }

            if group.isExpanded {
                GeometryReader { proxy in
                    let columns = appGridColumns(for: proxy.size.width)
                    ScrollView(.vertical) {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                            ForEach(members) { member in
                                switch member.content {
                                case .app(let appMember):
                                    appCard(
                                        for: appMember.app,
                                        showsGroupBadge: false,
                                        supportsHoverBadge: true,
                                        hoverCardID: "group:\(group.id.uuidString):app:\(appMember.app.id)",
                                        isOffline: !appMember.isRunning,
                                        removeAction: {
                                            removeAppFromGroup(bundleID: appMember.app.id)
                                        }
                                    )
                                case .url(let item):
                                    urlCard(
                                        for: item,
                                        hoverCardID: "group:\(group.id.uuidString):url:\(item.id.uuidString)",
                                        removeAction: {
                                            removeURLFromGroup(urlID: item.id)
                                        }
                                    )
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(height: 148)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .onDrop(of: [UTType.text.identifier], isTargeted: nil) { providers in
            handleDrop(providers: providers, groupID: group.id)
        }
    }

    private var groupsTitle: String {
        groups.isEmpty ? AppLocalization.localizedString("Groups") : AppLocalization.format("Groups (%d)", groups.count)
    }

    private func appGridColumns(for containerWidth: CGFloat) -> [GridItem] {
        let safeWidth = max(containerWidth, 0)
        let itemWidth = max(120, floor((safeWidth - 30) / 4))
        return Array(repeating: GridItem(.fixed(itemWidth), spacing: 10), count: 4)
    }

    private func refreshApps() {
        let runningApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }

        var uniqueByBundleID: [String: BranchApp] = [:]
        for running in runningApps {
            guard let bundleID = running.bundleIdentifier, !bundleID.isEmpty else { continue }
            let icon = running.icon ?? NSWorkspace.shared.icon(forFile: running.bundleURL?.path ?? "")
            let name = running.localizedName ?? bundleID
            uniqueByBundleID[bundleID] = BranchApp(id: bundleID, name: name, icon: icon)
        }

        apps = uniqueByBundleID.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func appRefForBundleID(_ bundleID: String) -> AppBranchAppRef {
        if let running = apps.first(where: { $0.id == bundleID }) {
            return AppBranchAppRef(bundleID: bundleID, displayName: running.name)
        }
        if let app = appFromSystem(bundleID: bundleID, fallbackName: bundleID) {
            return AppBranchAppRef(bundleID: bundleID, displayName: app.name)
        }
        return AppBranchAppRef(bundleID: bundleID, displayName: bundleID)
    }

    private func appFromSystem(bundleID: String, fallbackName: String) -> BranchApp? {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        let displayName = Bundle(url: appURL)?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        let bundleName = Bundle(url: appURL)?.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String
        let resolvedName = displayName ?? bundleName ?? appURL.deletingPathExtension().lastPathComponent
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        return BranchApp(
            id: bundleID,
            name: resolvedName.isEmpty ? fallbackName : resolvedName,
            icon: icon
        )
    }

    private func defaultAppIcon() -> NSImage {
        NSWorkspace.shared.icon(for: .application)
    }

    private func groupForApp(bundleID: String) -> AppBranchGroup? {
        groups.first { $0.appBundleIDs.contains(bundleID) }
    }

    private func groupForURL(id: UUID) -> AppBranchGroup? {
        groups.first { $0.urlPatternIDs.contains(id) }
    }

    private func groupMembers(group: AppBranchGroup) -> [GroupMember] {
        let runningByBundleID = Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0) })
        let urlSet = Set(group.urlPatternIDs)

        let appMembers = group.appRefs.map { ref in
            let runningApp = runningByBundleID[ref.bundleID]
            let resolvedApp = runningApp ?? appFromSystem(bundleID: ref.bundleID, fallbackName: ref.displayName)
                ?? BranchApp(
                    id: ref.bundleID,
                    name: ref.displayName.isEmpty ? ref.bundleID : ref.displayName,
                    icon: defaultAppIcon()
                )
            return GroupMember(content: .app(GroupAppMember(app: resolvedApp, isRunning: runningApp != nil)))
        }
        let urlMembers = urlItems
            .filter { urlSet.contains($0.id) }
            .map { GroupMember(content: .url($0)) }
        return appMembers + urlMembers
    }

    private func setGroupExpanded(groupID: UUID, expanded: Bool) {
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else { return }
        groups[index].isExpanded = expanded
    }

    private func assignApp(bundleID: String, to groupID: UUID) {
        for index in groups.indices {
            groups[index].appBundleIDs.removeAll { $0 == bundleID }
            groups[index].appRefs.removeAll { $0.bundleID == bundleID }
        }
        guard let targetIndex = groups.firstIndex(where: { $0.id == groupID }) else { return }
        if !groups[targetIndex].appBundleIDs.contains(bundleID) {
            groups[targetIndex].appBundleIDs.append(bundleID)
        }
        if !groups[targetIndex].appRefs.contains(where: { $0.bundleID == bundleID }) {
            groups[targetIndex].appRefs.append(appRefForBundleID(bundleID))
        }
    }

    private func assignURL(urlID: UUID, to groupID: UUID) {
        for index in groups.indices {
            groups[index].urlPatternIDs.removeAll { $0 == urlID }
        }
        guard let targetIndex = groups.firstIndex(where: { $0.id == groupID }) else { return }
        if !groups[targetIndex].urlPatternIDs.contains(urlID) {
            groups[targetIndex].urlPatternIDs.append(urlID)
        }
    }

    private func removeAppFromGroup(bundleID: String) {
        for index in groups.indices {
            groups[index].appBundleIDs.removeAll { $0 == bundleID }
            groups[index].appRefs.removeAll { $0.bundleID == bundleID }
        }
    }

    private func removeURLFromGroup(urlID: UUID) {
        for index in groups.indices {
            groups[index].urlPatternIDs.removeAll { $0 == urlID }
        }
    }

    private func deleteURLItem(id: UUID) {
        urlItems.removeAll { $0.id == id }
        removeURLFromGroup(urlID: id)
    }

    private func deleteGroup(groupID: UUID) {
        groups.removeAll { $0.id == groupID }
    }

    private func saveGroup(state: AppBranchModal) {
        let trimmedName = groupNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            modalErrorMessage = AppLocalization.localizedString("Group name is required.")
            return
        }

        switch state {
        case .createGroup:
            groups.append(
                AppBranchGroup(
                    id: UUID(),
                    name: trimmedName,
                    prompt: groupPromptDraft,
                    appBundleIDs: [],
                    appRefs: [],
                    urlPatternIDs: [],
                    isExpanded: true
                )
            )
        case .editGroup(let groupID):
            guard let index = groups.firstIndex(where: { $0.id == groupID }) else { break }
            groups[index].name = trimmedName
            groups[index].prompt = groupPromptDraft
        default:
            break
        }

        modal = nil
    }

    private func saveAddedURLs() {
        let entries = urlDraft
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !entries.isEmpty else {
            modalErrorMessage = AppLocalization.localizedString("Enter at least one URL pattern.")
            return
        }

        let canonicalEntries = entries.map(canonicalizedPattern)
        let normalizedInput = canonicalEntries.map(normalizedPattern)
        if Set(normalizedInput).count != normalizedInput.count {
            modalErrorMessage = AppLocalization.localizedString("Duplicate URL patterns detected in input.")
            return
        }

        if let invalid = canonicalEntries.first(where: { !isValidWildcardURLPattern($0) }) {
            modalErrorMessage = AppLocalization.format("Invalid URL pattern: %@. Use wildcard format like google.com/*.", invalid)
            return
        }

        let existing = Set(urlItems.map { normalizedPattern($0.pattern) })
        if normalizedInput.contains(where: { existing.contains($0) }) {
            modalErrorMessage = AppLocalization.localizedString("Some URL patterns already exist.")
            return
        }

        let newItems = canonicalEntries.map { BranchURLItem(id: UUID(), pattern: $0) }
        urlItems.append(contentsOf: newItems)
        modal = nil
    }

    private func saveEditedURL(urlID: UUID) {
        let canonical = canonicalizedPattern(urlDraft)
        guard !canonical.isEmpty else {
            modalErrorMessage = AppLocalization.localizedString("URL pattern is required.")
            return
        }

        guard isValidWildcardURLPattern(canonical) else {
            modalErrorMessage = AppLocalization.localizedString("Invalid URL pattern. Use wildcard format like google.com/*.")
            return
        }

        let normalized = normalizedPattern(canonical)
        let others = Set(urlItems.filter { $0.id != urlID }.map { normalizedPattern($0.pattern) })
        if others.contains(normalized) {
            modalErrorMessage = AppLocalization.localizedString("URL pattern already exists.")
            return
        }

        guard let index = urlItems.firstIndex(where: { $0.id == urlID }) else {
            modal = nil
            return
        }
        urlItems[index].pattern = canonical
        modal = nil
    }

    private func canonicalizedPattern(_ value: String) -> String {
        var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.hasPrefix("https://") {
            normalized.removeFirst("https://".count)
        } else if normalized.hasPrefix("http://") {
            normalized.removeFirst("http://".count)
        }
        if !normalized.contains("/") {
            normalized += "/*"
        } else if normalized.hasSuffix("/") {
            normalized += "*"
        }
        return normalized
    }

    private func normalizedPattern(_ value: String) -> String {
        canonicalizedPattern(value)
    }

    private func isValidWildcardURLPattern(_ pattern: String) -> Bool {
        let value = normalizedPattern(pattern)
        guard !value.isEmpty else { return false }
        guard !value.contains("://") else { return false }
        guard !value.contains(" ") else { return false }
        guard value.contains(".") else { return false }
        guard value.contains("/") else { return false }

        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-._/*")
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private func loadPersistedGroups() {
        guard let data = UserDefaults.standard.data(forKey: AppPreferenceKey.appBranchGroups) else {
            return
        }
        do {
            groups = try JSONDecoder().decode([AppBranchGroup].self, from: data)
        } catch {
            groups = []
        }
    }

    private func saveGroups() {
        do {
            let data = try JSONEncoder().encode(groups)
            UserDefaults.standard.set(data, forKey: AppPreferenceKey.appBranchGroups)
        } catch {
            VoxtLog.error("Failed to persist app branch groups: \(error.localizedDescription)")
        }
    }

    private func loadPersistedURLs() {
        guard let data = UserDefaults.standard.data(forKey: AppPreferenceKey.appBranchURLs) else {
            return
        }
        do {
            urlItems = try JSONDecoder().decode([BranchURLItem].self, from: data).map {
                BranchURLItem(id: $0.id, pattern: canonicalizedPattern($0.pattern))
            }
        } catch {
            urlItems = []
        }
    }

    private func saveURLs() {
        do {
            let data = try JSONEncoder().encode(urlItems)
            UserDefaults.standard.set(data, forKey: AppPreferenceKey.appBranchURLs)
        } catch {
            VoxtLog.error("Failed to persist app branch URLs: \(error.localizedDescription)")
        }
    }

    private func handleDrop(providers: [NSItemProvider], groupID: UUID) -> Bool {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else {
            return false
        }

        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let rawValue = object as? NSString else { return }
            let value = rawValue as String
            DispatchQueue.main.async {
                if value.hasPrefix("app:") {
                    let bundleID = String(value.dropFirst(4))
                    assignApp(bundleID: bundleID, to: groupID)
                    draggingAppID = nil
                } else if value.hasPrefix("url:") {
                    let rawID = String(value.dropFirst(4))
                    if let urlID = UUID(uuidString: rawID) {
                        assignURL(urlID: urlID, to: groupID)
                    }
                }
            }
        }
        return true
    }

    @ViewBuilder
    private func modalView(for currentModal: AppBranchModal) -> some View {
        switch currentModal {
        case .createGroup, .editGroup:
            GroupEditorSheet(
                title: currentModal.title,
                actionTitle: currentModal.actionTitle,
                name: $groupNameDraft,
                prompt: $groupPromptDraft,
                errorMessage: modalErrorMessage,
                onCancel: {
                    modal = nil
                },
                onSave: {
                    saveGroup(state: currentModal)
                }
            )
            .frame(width: 460, height: 410)

        case .addURLs:
            URLBatchEditorSheet(
                title: currentModal.title,
                actionTitle: currentModal.actionTitle,
                text: $urlDraft,
                errorMessage: modalErrorMessage,
                onCancel: {
                    modal = nil
                },
                onSave: {
                    saveAddedURLs()
                }
            )
            .frame(width: 500, height: 420)

        case .editURL(let urlID):
            URLBatchEditorSheet(
                title: currentModal.title,
                actionTitle: currentModal.actionTitle,
                text: $urlDraft,
                errorMessage: modalErrorMessage,
                onCancel: {
                    modal = nil
                },
                onSave: {
                    saveEditedURL(urlID: urlID)
                }
            )
            .frame(width: 500, height: 360)

        case .urlDetail(let item):
            URLDetailSheet(
                pattern: item.pattern,
                onClose: { modal = nil }
            )
            .frame(width: 520, height: 260)
        }
    }
}

