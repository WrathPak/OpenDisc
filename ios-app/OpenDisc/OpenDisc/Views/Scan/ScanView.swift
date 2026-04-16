import SwiftUI

struct ScanView: View {
    @Environment(BLEManager.self) private var bleManager
    @State private var showError = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                scanAnimation

                Text("Searching for OpenDisc...")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                if bleManager.discoveredPeripherals.isEmpty {
                    Text("Make sure your OpenDisc is powered on")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                } else {
                    deviceList
                }

                Spacer()
            }
            .padding()
            .navigationTitle("OpenDisc")
            .onAppear { bleManager.startScanning() }
            .onDisappear { bleManager.stopScanning() }
            .onChange(of: bleManager.error != nil) { _, hasError in
                showError = hasError
            }
            .alert("Bluetooth Error", isPresented: $showError) {
                Button("OK") { bleManager.error = nil }
            } message: {
                Text(bleManager.error?.localizedDescription ?? "")
            }
        }
    }

    private var scanAnimation: some View {
        ZStack {
            PulseRing(index: 0, isScanning: bleManager.connectionState == .scanning)
            PulseRing(index: 1, isScanning: bleManager.connectionState == .scanning)
            PulseRing(index: 2, isScanning: bleManager.connectionState == .scanning)

            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 36))
                .foregroundStyle(Color.accentColor)
        }
    }

    private var deviceList: some View {
        VStack(spacing: 8) {
            ForEach(bleManager.discoveredPeripherals) { device in
                Button {
                    HapticManager.buttonPress()
                    bleManager.connect(to: device.peripheral)
                } label: {
                    DeviceRow(
                        device: device,
                        isConnecting: bleManager.connectionState == .connecting
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .glassEffect(.regular.interactive())
            }
        }
    }
}

private struct PulseRing: View {
    let index: Int
    let isScanning: Bool

    var body: some View {
        let size = CGFloat(80 + index * 40)
        let opacity = 0.3 - Double(index) * 0.1
        Circle()
            .stroke(Color.accentColor.opacity(opacity), lineWidth: 2)
            .frame(width: size, height: size)
            .scaleEffect(isScanning ? 1.2 : 0.8)
            .animation(
                .easeInOut(duration: 1.5)
                .repeatForever(autoreverses: true)
                .delay(Double(index) * 0.3),
                value: isScanning
            )
    }
}
