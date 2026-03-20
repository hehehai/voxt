import SwiftUI
import AppKit
import UniformTypeIdentifiers

extension AppEnhancementSettingsView {
    var sourceListCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SourceTabPicker(selectedTab: $sourceTab)

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

    var appsGrid: some View {
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

    var urlsList: some View {
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

    func urlRow(_ item: BranchURLItem) -> some View {
        let group = groupForURL(id: item.id)

        return URLPatternRowView(
            pattern: item.pattern,
            groupName: group?.name,
            onRemoveFromGroup: group == nil ? nil : { removeURLFromGroup(urlID: item.id) },
            onEdit: {
                urlDraft = item.pattern
                modalErrorMessage = nil
                modal = .editURL(item.id)
            },
            onDelete: {
                deleteURLItem(id: item.id)
            }
        )
    }

    var groupListCard: some View {
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

    func appCard(
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
                        : (
                            isOffline
                                ? Color.primary.opacity(0.18)
                                : (isAssigned ? Color.accentColor.opacity(0.55) : Color.primary.opacity(0.10))
                        ),
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

    func urlCard(
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

    func groupCard(for group: AppBranchGroup) -> some View {
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

    var groupsTitle: String {
        groups.isEmpty ? AppLocalization.localizedString("Groups") : AppLocalization.format("Groups (%d)", groups.count)
    }

    func appGridColumns(for containerWidth: CGFloat) -> [GridItem] {
        let safeWidth = max(containerWidth, 0)
        let itemWidth = max(120, floor((safeWidth - 30) / 4))
        return Array(repeating: GridItem(.fixed(itemWidth), spacing: 10), count: 4)
    }

    @ViewBuilder
    func modalView(for currentModal: AppBranchModal) -> some View {
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
