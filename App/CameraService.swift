import SwiftUI
import AVFoundation
import UIKit

enum CameraMode {
    case lens
    case infrared
}

struct Hotspot: Identifiable {
    let id: Int
    let x: CGFloat
    let y: CGFloat
    let strength: CGFloat
}

final class CameraService: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()

    @Published var hotspots: [Hotspot] = []
    @Published var ambient: Double = 0
    @Published var peakHotspots: Int = 0
    @Published var frames: Int = 0
    @Published var denied = false

    private let queue = DispatchQueue(label: "lensguard.camera")
    private let output = AVCaptureVideoDataOutput()
    private var device: AVCaptureDevice?

    // Touched only on `queue`
    private var mode: CameraMode = .lens
    private var persistence: [Int] = []
    private var frameCount = 0
    private var peak = 0

    private static let grid = 32
    private static let confirmFrames = 6
    private static let warmupFrames = 30

    func start(mode: CameraMode) {
        hotspots = []
        ambient = 0
        peakHotspots = 0
        frames = 0
        AVCaptureDevice.requestAccess(for: .video) { [weak self] (granted: Bool) in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.denied = !granted
            }
            guard granted else { return }
            self.queue.async {
                self.configureAndRun(mode: mode)
            }
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.releaseDevice()
            if self.session.isRunning {
                self.session.stopRunning()
            }
            DispatchQueue.main.async {
                self.hotspots = []
            }
        }
    }

    private func configureAndRun(mode: CameraMode) {
        self.mode = mode
        persistence = [Int](repeating: 0, count: CameraService.grid * CameraService.grid)
        frameCount = 0
        peak = 0

        let position: AVCaptureDevice.Position = (mode == .lens) ? .back : .front

        session.beginConfiguration()
        if session.canSetSessionPreset(.hd1280x720) {
            session.sessionPreset = .hd1280x720
        }
        for existing in session.inputs {
            session.removeInput(existing)
        }
        if let cam = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
           let input = try? AVCaptureDeviceInput(device: cam),
           session.canAddInput(input) {
            session.addInput(input)
            device = cam
        }
        if !session.outputs.contains(output) {
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: queue)
            if session.canAddOutput(output) {
                session.addOutput(output)
            }
        }
        if let conn = output.connection(with: .video) {
            if conn.isVideoRotationAngleSupported(90) {
                conn.videoRotationAngle = 90
            }
            if conn.isVideoMirroringSupported {
                conn.automaticallyAdjustsVideoMirroring = false
                conn.isVideoMirrored = (position == .front)
            }
        }
        session.commitConfiguration()

        prepareDevice(lens: mode == .lens)
        if !session.isRunning {
            session.startRunning()
        }
    }

    private func prepareDevice(lens: Bool) {
        guard let cam = device else { return }
        do {
            try cam.lockForConfiguration()
            if lens {
                if cam.hasTorch {
                    try cam.setTorchModeOn(level: 1.0)
                }
                let bias: Float = max(cam.minExposureTargetBias, -3.0)
                cam.setExposureTargetBias(bias, completionHandler: nil)
            }
            cam.unlockForConfiguration()
        } catch {
        }
    }

    private func releaseDevice() {
        guard let cam = device else { return }
        do {
            try cam.lockForConfiguration()
            if cam.hasTorch {
                cam.torchMode = .off
            }
            cam.setExposureTargetBias(0, completionHandler: nil)
            cam.unlockForConfiguration()
        } catch {
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let px = base.assumingMemoryBound(to: UInt8.self)
        let g = CameraService.grid
        let cells = g * g
        let isLens = (mode == .lens)
        let brightThreshold = isLens ? 250 : 235

        var bright = [Int](repeating: 0, count: cells)
        var purple = [Int](repeating: 0, count: cells)
        var total = [Int](repeating: 0, count: cells)
        var lumaSum = [Int](repeating: 0, count: cells)
        var allSum = 0
        var allCount = 0

        let step = 4
        var y = 0
        while y < height {
            let row = min(g - 1, y * g / height)
            var x = 0
            while x < width {
                let o = y * rowBytes + x * 4
                let b = Int(px[o])
                let gr = Int(px[o + 1])
                let r = Int(px[o + 2])
                let luma = (r * 3 + gr * 6 + b) / 10
                let idx = row * g + min(g - 1, x * g / width)
                total[idx] += 1
                lumaSum[idx] += luma
                allSum += luma
                allCount += 1
                if luma >= brightThreshold {
                    bright[idx] += 1
                }
                if b > 170 && r > 110 && gr + 30 < b {
                    purple[idx] += 1
                }
                x += step
            }
            y += step
        }

        let ambientLevel: Double = allCount > 0 ? Double(allSum) / Double(allCount) : 0
        frameCount += 1

        var candidates: [Hotspot] = []
        for idx in 0..<cells {
            let t = Double(max(total[idx], 1))
            var hit = false
            var strength: Double = 0
            if isLens {
                let frac = Double(bright[idx]) / t
                let cellMean = Double(lumaSum[idx]) / t
                hit = ambientLevel < 150 && bright[idx] >= 2 && frac < 0.25 && cellMean < 170
                strength = min(1.0, Double(bright[idx]) / 8.0)
            } else {
                let count = bright[idx] + purple[idx]
                hit = ambientLevel < 90 && count >= 3 && Double(bright[idx]) / t < 0.3
                strength = min(1.0, Double(count) / 10.0)
            }
            if hit {
                persistence[idx] = min(persistence[idx] + 1, 30)
            } else {
                persistence[idx] = max(persistence[idx] - 1, 0)
            }
            if persistence[idx] >= CameraService.confirmFrames {
                let col = idx % g
                let rowIdx = idx / g
                candidates.append(Hotspot(
                    id: idx,
                    x: (CGFloat(col) + 0.5) / CGFloat(g),
                    y: (CGFloat(rowIdx) + 0.5) / CGFloat(g),
                    strength: CGFloat(strength)
                ))
            }
        }

        candidates.sort { (a: Hotspot, b: Hotspot) -> Bool in a.strength > b.strength }
        var accepted: [Hotspot] = []
        for c in candidates {
            var tooClose = false
            for a in accepted {
                if abs(a.x - c.x) < 0.1 && abs(a.y - c.y) < 0.1 {
                    tooClose = true
                    break
                }
            }
            if !tooClose && accepted.count < 8 {
                accepted.append(c)
            }
        }

        if frameCount > CameraService.warmupFrames {
            peak = max(peak, accepted.count)
        }

        if frameCount % 3 == 0 {
            let snapshot = accepted
            let amb = ambientLevel
            let peakNow = peak
            let count = frameCount
            DispatchQueue.main.async {
                self.hotspots = snapshot
                self.ambient = amb
                self.peakHotspots = peakNow
                self.frames = count
            }
        }
    }
}

final class PreviewUIView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        return layer as! AVCaptureVideoPreviewLayer
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
    }
}
