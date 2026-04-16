import SwiftUI

struct IMUDiagView: View {
    @Environment(BLEManager.self) private var bleManager

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let diag = bleManager.imuDiag {
                    registerRow("WHO_AM_I", diag.whoami)
                    registerRow("CTRL1", diag.ctrl1)
                    registerRow("CTRL2", diag.ctrl2)
                    registerRow("CTRL6", diag.ctrl6)
                    registerRow("CTRL8", diag.ctrl8)
                    registerRow("CTRL9", diag.ctrl9)
                    registerRow("CTRL1_XL_HG", diag.ctrl1_xl_hg)

                    Divider().padding(.vertical, 8)

                    registerRow("Gyro FS", diag.fs_g)
                    registerRow("Accel FS", diag.fs_xl)
                } else {
                    ProgressView("Loading diagnostics...")
                }
            }
            .padding()
        }
        .navigationTitle("IMU Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { bleManager.requestIMUDiag() }
    }

    private func registerRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(.subheadline, design: .monospaced))
                .fontWeight(.semibold)
        }
        .padding(12)
        .glassEffect(.regular)
    }
}
