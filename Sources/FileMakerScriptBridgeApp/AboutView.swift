import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(
                        LinearGradient(
                            colors: [.indigo, .blue, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 76, height: 76)
                Image(systemName: "arrow.left.arrow.right.square.fill")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 5) {
                Text("FileMaker Script Bridge")
                    .font(.title2.weight(.semibold))
                Text("Version 2026.08.11 · Developer: SCKC")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            GroupBox("GNU General Public License") {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("""
                        FileMaker Script Bridge
                        Copyright (C) 2026 SCKC

                        This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

                        This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

                        You should have received a copy of the GNU General Public License along with this program. If not, see:
                        """)
                        Link("https://www.gnu.org/licenses/", destination: URL(string: "https://www.gnu.org/licenses/")!)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(.subheadline)
                    .textSelection(.enabled)
                }
                .frame(height: 235)
            }

            GroupBox("Independent software disclaimer") {
                Text("This app is developed independently by SCKC. It is not made by, affiliated with, endorsed by, or supported by Claris International Inc. FileMaker and FileMaker Pro are trademarks of Claris International Inc.")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(24)
        .frame(width: 560)
    }
}
