//
//  MainChromeView.swift
//  ImageOptim
//
//  SwiftUI replacement for the bottom control strip in Base.lproj/ImageOptim.xib: the Add
//  button (id 423), status label (id 294), progress spinner (id 428), Again button (id 586),
//  and Settings gear (id Chx-W4-45F). Those AppKit controls stay in the xib but are hidden at
//  runtime in -[ImageOptimController awakeFromNib] and this view is hosted in their place —
//  see MainChromeViewFactory below and ImageOptimController.m. The file list table and the
//  drag-and-drop empty state (FadeView/DragDropImageView) are untouched; that's the next
//  phase of the rewrite.
//
//  The "Add" button's old `enabled` binding pointed at a `canAdd` key that doesn't exist
//  anywhere on FilesController (confirmed by grep) — Cocoa Bindings just silently no-ops on
//  an unresolvable keypath, so in practice the button was always enabled. This reproduces
//  that actual behavior rather than the aspirational one implied by the binding's name.
//

import SwiftUI

struct MainChromeView: View {
    @ObservedObject var store: FileListStore

    let onAdd: () -> Void
    let onAgain: (_ optimizedOnly: Bool) -> Void
    let onSettings: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onAdd) {
                Image(systemName: "plus")
            }
            .help("Add")
            .accessibilityLabel("Add new files or directories")

            Group {
                if store.statusSelectable {
                    Text(store.statusText)
                        .textSelection(.enabled)
                } else {
                    Text(store.statusText)
                }
            }
            .font(.system(size: 11))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)

            // Both this spinner and the Settings button below flip on the same isBusy change,
            // on either side of the Again button. Conditionally inserting/removing two sibling
            // views on the same state change, with no reserved space, is exactly what produced
            // an overlapping transition frame right as a job finished (isBusy true -> false)
            // and Settings needed to fade in at the same moment the spinner needed to
            // disappear. Fixed space + opacity instead of insertion/removal — the HStack's
            // layout can never shift here, so there's nothing for a transient frame to overlap.
            ProgressView()
                .controlSize(.small)
                .frame(width: 16, height: 16)
                .opacity(store.isBusy ? 1 : 0)

            Button {
                onAgain(NSEvent.modifierFlags.contains(.option))
            } label: {
                Label("Again", systemImage: "arrow.clockwise")
            }
            .help("Run optimizations again")
            .disabled(store.rows.isEmpty)

            Button(action: onSettings) {
                Image(systemName: "ellipsis.circle")
            }
            .help("Settings")
            .accessibilityLabel("Show settings")
            .opacity(store.isBusy ? 0 : 1)
            .disabled(store.isBusy)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}
