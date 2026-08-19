//
//  ScaffoldPlaceholderView.swift
//  ImageOptim
//
//  Scaffolding-phase placeholder: proves Swift/SwiftUI compiles in the ImageOptim target
//  and that FileListStore correctly mirrors FilesController. Not hosted in any window yet
//  (that starts with the Preferences window rewrite) — see the SwiftUI rewrite plan.
//

import SwiftUI

struct ScaffoldPlaceholderView: View {
    @ObservedObject var store: FileListStore

    var body: some View {
        VStack(spacing: 8) {
            Text("SwiftUI scaffold online")
                .font(.headline)
            Text("\(store.rows.count) file(s) in queue")
                .foregroundStyle(.secondary)
            if store.isBusy {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding()
        .frame(minWidth: 240, minHeight: 120)
    }
}
