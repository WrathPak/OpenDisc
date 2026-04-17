import SwiftUI
import SceneKit
import simd

/// 3D visualization of a reconstructed throw trajectory.
///
/// Presented as a sheet or fullscreen from `ThrowDetailView`. Renders the
/// disc's path through space with speed-gradient coloring, keyframe disc
/// models showing orientation, and a release marker.
struct TrajectoryView: View {
    let trajectory: Trajectory?
    let errorMessage: String?
    let throwData: ThrowData

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let trajectory {
                    TrajectorySceneView(trajectory: trajectory)
                        .ignoresSafeArea(edges: .bottom)
                        .overlay(alignment: .bottom) {
                            legend.padding(.bottom, 24)
                        }
                        .overlay(alignment: .topLeading) {
                            diagnostics(trajectory: trajectory)
                                .padding(.leading, 12)
                                .padding(.top, 8)
                        }
                } else {
                    unavailablePanel
                }
            }
            .navigationTitle("3D Trajectory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var unavailablePanel: some View {
        let samples = throwData.decodedSamples?.count ?? 0
        let rawBytes = throwData.rawSamples?.count ?? 0
        let rows: [(String, String)] = [
            ("Reason", errorMessage ?? "Unknown — trajectory not produced."),
            ("Samples decoded", "\(samples)"),
            ("Raw bytes", "\(rawBytes)"),
            ("releaseIdx", "\(throwData.releaseIdx)"),
            ("calRx, calRy", String(format: "%.4f, %.4f", throwData.calRx, throwData.calRy)),
            ("mph (firmware)", String(format: "%.2f", throwData.mph)),
            ("durationMS", "\(throwData.durationMS)"),
            ("launchAngle", String(format: "%.2f°", throwData.launchAngle))
        ]
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Trajectory unavailable")
                        .font(.headline)
                }
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(rows, id: \.0) { row in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.0)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(row.1)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))

                Text("Tip: calRx/calRy of 0 means the gyro bias calibration never ran — integration will drift. mph near zero + durationMS near zero means the firmware didn't detect a real throw.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }

    private func diagnostics(trajectory: Trajectory) -> some View {
        let points = trajectory.points
        let moving = points.filter { $0.speed > 0.05 }.count
        let extent = trajectory.bounds.max - trajectory.bounds.min
        let speeds = points.map { $0.speed }
        let sMin = speeds.min() ?? 0
        let sMax = speeds.max() ?? 0
        let lines = [
            "points: \(points.count)  moving: \(moving)",
            String(format: "extent m: %.2f×%.2f×%.2f", extent.x, extent.y, extent.z),
            "releaseIdx: \(trajectory.releaseIndex)",
            String(format: "speed m/s: %.2f…%.2f", sMin, sMax)
        ]
        return VStack(alignment: .leading, spacing: 2) {
            ForEach(lines, id: \.self) { Text($0) }
        }
        .font(.caption2.monospaced())
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var legend: some View {
        HStack(spacing: 16) {
            legendItem(color: .blue, label: "Slow")
            legendItem(color: .green, label: "Mid")
            legendItem(color: .red, label: "Fast")
            legendItem(color: .yellow, label: "Release")
        }
        .font(.caption)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
        }
    }
}

// MARK: - SceneKit Host

private struct TrajectorySceneView: UIViewRepresentable {
    let trajectory: Trajectory

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .black
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.antialiasingMode = .multisampling4X
        view.scene = buildScene()
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        uiView.scene = buildScene()
    }

    private func buildScene() -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = UIColor.black

        // Ambient light for color visibility
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 400
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        // Directional light for disc shading
        let sun = SCNLight()
        sun.type = .directional
        sun.intensity = 800
        let sunNode = SCNNode()
        sunNode.light = sun
        sunNode.eulerAngles = SCNVector3(-Float.pi / 3, Float.pi / 4, 0)
        scene.rootNode.addChildNode(sunNode)

        // Ground grid for reference
        scene.rootNode.addChildNode(makeGroundGrid())

        // Trajectory path
        let pathNode = makePathNode()
        scene.rootNode.addChildNode(pathNode)

        // Disc keyframes (every ~100 ms)
        let discNode = makeDiscKeyframes()
        scene.rootNode.addChildNode(discNode)

        // Release marker
        if let releasePoint = releasePoint() {
            scene.rootNode.addChildNode(makeReleaseMarker(at: releasePoint))
        }

        // Camera
        scene.rootNode.addChildNode(makeCamera())

        return scene
    }

    // MARK: Scene construction

    private func makePathNode() -> SCNNode {
        let moving = trajectory.points.filter { $0.speed > 0.05 }
        guard moving.count >= 2 else { return SCNNode() }

        let maxSpeed = max(moving.map { $0.speed }.max() ?? 1, 1)
        let parent = SCNNode()

        // Draw each segment as a thin cylinder, colored by the segment's speed.
        for idx in 0..<(moving.count - 1) {
            let a = moving[idx]
            let b = moving[idx + 1]
            let segment = makeSegment(from: a.position,
                                      to: b.position,
                                      speed: a.speed,
                                      maxSpeed: maxSpeed)
            parent.addChildNode(segment)
        }
        return parent
    }

    private func makeSegment(from a: SIMD3<Float>,
                             to b: SIMD3<Float>,
                             speed: Float,
                             maxSpeed: Float) -> SCNNode {
        let delta = b - a
        let length = simd_length(delta)
        guard length > 0.0001 else { return SCNNode() }

        let cyl = SCNCylinder(radius: 0.008, height: CGFloat(length))
        cyl.radialSegmentCount = 6
        cyl.firstMaterial?.diffuse.contents = speedColor(speed / maxSpeed)
        cyl.firstMaterial?.lightingModel = .constant
        let node = SCNNode(geometry: cyl)

        // Position at midpoint
        let mid = (a + b) * 0.5
        node.position = SCNVector3(mid.x, mid.z, -mid.y) // convert to SceneKit coord

        // Orient the cylinder along the segment direction.
        // SCNCylinder's default axis is +Y.
        let dirScene = SCNVector3(delta.x, delta.z, -delta.y)
        let up = SCNVector3(0, 1, 0)
        node.orientation = orientationFromTo(from: up, to: dirScene)
        return node
    }

    private func makeDiscKeyframes() -> SCNNode {
        let parent = SCNNode()
        let stride = max(1, trajectory.points.count / 20) // ~20 keyframes

        for idx in Swift.stride(from: 0, to: trajectory.points.count, by: stride) {
            let p = trajectory.points[idx]
            if p.speed < 0.05 && !p.isRelease { continue }

            let disc = SCNCylinder(radius: 0.105, height: 0.018)
            disc.firstMaterial?.diffuse.contents = UIColor(white: 0.85, alpha: 0.6)
            disc.firstMaterial?.transparency = 0.7
            let node = SCNNode(geometry: disc)

            node.position = SCNVector3(p.position.x, p.position.z, -p.position.y)

            // Apply orientation: disc body frame -> SceneKit world frame
            let q = p.orientation
            node.orientation = SCNQuaternion(q.imag.x, q.imag.z, -q.imag.y, q.real)
            parent.addChildNode(node)
        }
        return parent
    }

    private func makeReleaseMarker(at position: SIMD3<Float>) -> SCNNode {
        let sphere = SCNSphere(radius: 0.03)
        sphere.firstMaterial?.diffuse.contents = UIColor.yellow
        sphere.firstMaterial?.emission.contents = UIColor.yellow
        let node = SCNNode(geometry: sphere)
        node.position = SCNVector3(position.x, position.z, -position.y)
        return node
    }

    private func makeGroundGrid() -> SCNNode {
        let parent = SCNNode()
        let extent: Float = 3.0
        let spacing: Float = 0.5
        let gridMat = SCNMaterial()
        gridMat.diffuse.contents = UIColor(white: 0.2, alpha: 1.0)
        gridMat.lightingModel = .constant

        var x: Float = -extent
        while x <= extent {
            let line = SCNBox(width: 0.005, height: 0.001, length: CGFloat(extent * 2), chamferRadius: 0)
            line.firstMaterial = gridMat
            let node = SCNNode(geometry: line)
            node.position = SCNVector3(x, 0, 0)
            parent.addChildNode(node)
            x += spacing
        }

        var z: Float = -extent
        while z <= extent {
            let line = SCNBox(width: CGFloat(extent * 2), height: 0.001, length: 0.005, chamferRadius: 0)
            line.firstMaterial = gridMat
            let node = SCNNode(geometry: line)
            node.position = SCNVector3(0, 0, z)
            parent.addChildNode(node)
            z += spacing
        }
        return parent
    }

    private func makeCamera() -> SCNNode {
        let camera = SCNCamera()
        camera.fieldOfView = 55
        camera.zNear = 0.05
        camera.zFar = 200

        let cameraNode = SCNNode()
        cameraNode.camera = camera

        // Frame the trajectory bounds
        let size = trajectory.bounds.max - trajectory.bounds.min
        let maxDim = max(simd_length(size), 1.5)
        let center = (trajectory.bounds.max + trajectory.bounds.min) * 0.5

        cameraNode.position = SCNVector3(
            center.x + maxDim * 0.8,
            max(center.z, 0.5) + maxDim * 0.5,
            -center.y + maxDim * 1.2
        )
        cameraNode.look(at: SCNVector3(center.x, center.z, -center.y))
        return cameraNode
    }

    // MARK: Helpers

    private func releasePoint() -> SIMD3<Float>? {
        trajectory.points.first(where: { $0.isRelease })?.position
    }

    private func speedColor(_ t: Float) -> UIColor {
        // blue -> green -> red gradient
        let clamped = min(max(t, 0), 1)
        if clamped < 0.5 {
            let u = CGFloat(clamped * 2)
            return UIColor(red: 0, green: u, blue: 1 - u, alpha: 1)
        } else {
            let u = CGFloat((clamped - 0.5) * 2)
            return UIColor(red: u, green: 1 - u, blue: 0, alpha: 1)
        }
    }

    private func orientationFromTo(from: SCNVector3, to: SCNVector3) -> SCNQuaternion {
        let fromV = simd_normalize(SIMD3<Float>(from.x, from.y, from.z))
        let toV = simd_normalize(SIMD3<Float>(to.x, to.y, to.z))
        let dot = simd_dot(fromV, toV)
        if dot > 0.9999 {
            return SCNQuaternion(0, 0, 0, 1)
        }
        if dot < -0.9999 {
            let axis = abs(fromV.x) < 0.9
                ? simd_normalize(simd_cross(fromV, SIMD3<Float>(1, 0, 0)))
                : simd_normalize(simd_cross(fromV, SIMD3<Float>(0, 1, 0)))
            return SCNQuaternion(axis.x, axis.y, axis.z, 0)
        }
        let axis = simd_normalize(simd_cross(fromV, toV))
        let angle = acosf(dot)
        let half = angle * 0.5
        let s = sinf(half)
        return SCNQuaternion(axis.x * s, axis.y * s, axis.z * s, cosf(half))
    }
}
