//
//  FileListView.swift
//  ImageOptim
//
//  SwiftUI replacement for the file list, retiring (in terms of what's actually shown —
//  see the note in ImageOptimController.m's -installSwiftFileList) MyTableView,
//  RevealButtonCell, DragDropImageView, and FadeView.
//
//  Uses List rather than Table: Table (macOS 12+) has no row-reorder API until later OS
//  versions, while List's .onMove(perform:) has been available since macOS 10.15 and matches
//  the original's free/manual reordering exactly (the original never supported column
//  sorting either — FilesController.moveObjectsInArrangedObjectsFromIndexes:toIndex: is a
//  plain manual move, not sort-driven). "Columns" below are a manually laid out HStack per
//  row rather than a real Table, which costs native resizable-column chrome but avoids
//  fighting Table's lack of onMove.
//
//  Not carried over from the old table in this pass: Copy / Copy as Data URI / Cut / Paste
//  (MyTableView.m's -copy:/-copyAsDataURI:/-cut:/-paste:) and the "Original Size"/"Best tool"
//  columns (hidden by default in the xib too, toggled via a header context menu the old
//  NSTableView provided for free — no SwiftUI equivalent built here).
//

import SwiftUI
import UniformTypeIdentifiers

struct FileListView: View {
    @ObservedObject var store: FileListStore
    @State private var isDropTargeted = false

    var body: some View {
        ZStack {
            if store.rows.isEmpty {
                EmptyDropView()
                    .transition(.opacity)
            } else {
                VStack(spacing: 0) {
                    FileListHeaderRow()
                    List(selection: $store.selection) {
                        ForEach(store.rows) { row in
                            FileRowView(store: store, row: row)
                                .tag(row.id)
                        }
                        .onMove { source, destination in
                            store.move(fromOffsets: source, toOffset: destination)
                        }
                    }
                    .listStyle(.inset)
                    .accessibilityLabel("List of files to optimize")
                    .onDeleteCommand {
                        store.delete(selectedRows())
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: store.rows.isEmpty)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
            return true
        }
    }

    private func selectedRows() -> [FileRowStore] {
        store.rows.filter { store.selection.contains($0.id) }
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        let group = DispatchGroup()
        var urls: [URL] = []
        let lock = NSLock()

        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url {
                    lock.lock()
                    urls.append(url)
                    lock.unlock()
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            guard !urls.isEmpty else { return }
            store.addURLs(urls)
        }
    }
}

// MARK: - Header

private struct FileListHeaderRow: View {
    var body: some View {
        HStack(spacing: 3) {
            Color.clear.frame(width: 22, height: 1) // status column has no header title
            Text("File")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Size")
                .frame(width: 85, alignment: .trailing)
                .help("Size of file after optimization")
            Text("Savings")
                .frame(width: 85, alignment: .trailing)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

// MARK: - Row

private struct FileRowView: View {
    @ObservedObject var store: FileListStore
    @ObservedObject var row: FileRowStore
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 3) {
            statusIcon
                .frame(width: 22)

            HStack(spacing: 4) {
                Text(row.fileName)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                // RevealButtonCell.m never actually hides this icon — it draws it at ~30%
                // opacity at rest and full opacity on hover (drawInteriorWithFrame:). An
                // appear/disappear button reads as a bigger, more distracting change than
                // that subtle brighten; keep it always present and animate opacity instead.
                Button {
                    store.revealInFinder([row])
                } label: {
                    Image(systemName: "arrow.forward.square")
                }
                .buttonStyle(.plain)
                .opacity(isHovering ? 1 : 0.3)
                .animation(.easeInOut(duration: 0.15), value: isHovering)
                .help(row.jobProxy.filePath.path)
                .accessibilityLabel("Reveal in Finder")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(row.byteCountFormattedOptimized)
                .frame(width: 85, alignment: .trailing)
                .monospacedDigit()

            Text(row.savingsText)
                .frame(width: 85, alignment: .trailing)
                .monospacedDigit()
        }
        .help(row.statusText ?? "")
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2) {
            performOnEffectiveTargets(row: row) { rows in
                store.revealInFinder(rows)
            }
        }
        .contextMenu {
            Button("Start Again") {
                performOnEffectiveTargets(row: row) { _ in store.startAgain(optimizedOnly: false) }
            }
            Button("Stop") {
                performOnEffectiveTargets(row: row) { _ in store.stopSelected() }
            }
            Divider()
            Button("Reveal in Finder") {
                performOnEffectiveTargets(row: row) { rows in store.revealInFinder(rows) }
            }
            Divider()
            Button("Delete") {
                performOnEffectiveTargets(row: row) { rows in store.delete(rows) }
            }
        }
    }

    // Right-click (or double-click) on a row outside the current selection should act on just
    // that row, matching MyTableView.m's -clickedRowSelection; on a row inside a multi-row
    // selection it should act on the whole selection.
    private func performOnEffectiveTargets(row: FileRowStore, _ action: ([FileRowStore]) -> Void) {
        if !store.selection.contains(row.id) {
            store.selection = [row.id]
        }
        let targets = store.rows.filter { store.selection.contains($0.id) }
        action(targets.isEmpty ? [row] : targets)
    }

    @ViewBuilder
    private var statusIcon: some View {
        if let name = row.statusImageName, let image = NSImage(named: name) {
            Image(nsImage: image)
                .accessibilityLabel(row.statusText ?? "Status")
        } else {
            Color.clear
        }
    }
}

// MARK: - Empty state (replaces FadeView + DragDropImageView)

private struct EmptyDropView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 48, weight: .thin))
                .foregroundStyle(.secondary.opacity(0.5))
            Text("Drag and drop image files onto the area above")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Drop images here")
    }
}
