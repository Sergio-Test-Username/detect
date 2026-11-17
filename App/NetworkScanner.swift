import SwiftUI
import Network
import Darwin

struct NetDevice: Identifiable {
    let id: String
    let ip: String
    let ports: [UInt16]
    let title: String
    let reason: String
    let server: String
    let risk: Risk
}

struct ProbeResult {
    let open: Bool
    let banner: String
}

final class ProbeState {
    private let lock = NSLock()
    private var fired = false
    private var opened = false

    func markOpen() {
        lock.lock()
        opened = true
        lock.unlock()
    }

    func isOpen() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return opened
    }

    func fire() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if fired { return false }
        fired = true
        return true
    }
}

private let cameraKeywords: [String] = [
    "ipcam", "webcam", "netcam", "camera", "hikvision", "dahua", "dvr", "nvr", "onvif",
    "reolink", "amcrest", "foscam", "uniview", "avtech", "wyze", "mjpg", "mjpeg",
    "axis communications", "yi home", "ezviz", "tapo", "imou", "lorex", "swann"
]

func probe(host: String, port: UInt16, timeout: Double) async -> ProbeResult {
    guard let nwPort = NWEndpoint.Port(rawValue: port) else {
        return ProbeResult(open: false, banner: "")
    }
    let payload: Data?
    switch port {
    case 80, 8080, 8000:
        payload = "GET / HTTP/1.0\r\nHost: \(host)\r\nUser-Agent: LensGuard\r\n\r\n".data(using: .utf8)
    case 554, 8554:
        payload = "OPTIONS rtsp://\(host):\(port)/ RTSP/1.0\r\nCSeq: 1\r\n\r\n".data(using: .utf8)
    default:
        payload = nil
    }

    return await withCheckedContinuation { (cont: CheckedContinuation<ProbeResult, Never>) in
        let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        let state = ProbeState()
        let finish: (String) -> Void = { (banner: String) in
            if state.fire() {
                let opened = state.isOpen()
                conn.cancel()
                cont.resume(returning: ProbeResult(open: opened, banner: banner))
            }
        }
        conn.stateUpdateHandler = { (newState: NWConnection.State) in
            switch newState {
            case .ready:
                state.markOpen()
                if let data = payload {
                    conn.send(content: data, completion: .contentProcessed({ (_: NWError?) in }))
                    conn.receive(minimumIncompleteLength: 1, maximumLength: 2048) { (received: Data?, _: NWConnection.ContentContext?, _: Bool, _: NWError?) in
                        let text: String = received.map { String(decoding: $0, as: UTF8.self) } ?? ""
                        finish(text)
                    }
                } else {
                    finish("")
                }
            case .failed(_):
                finish("")
            case .waiting(_):
                finish("")
            case .cancelled:
                finish("")
            default:
                break
            }
        }
        conn.start(queue: DispatchQueue.global())
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
            finish("")
        }
    }
}

func classify(ip: String, results: [(UInt16, ProbeResult)]) -> NetDevice {
    let ports: [UInt16] = results.map { $0.0 }.sorted()
    let rawBanner: String = results.map { $0.1.banner }.joined(separator: "\n")
    let lowered: String = rawBanner.lowercased()
    let hasStream: Bool = ports.contains(554) || ports.contains(8554)
    let hasDVR: Bool = ports.contains(37777) || ports.contains(34567) || ports.contains(8899)

    var server = ""
    let lines: [String] = rawBanner.components(separatedBy: "\n")
    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("server:") {
            server = String(trimmed.dropFirst(7)).trimmingCharacters(in: .whitespaces)
            break
        }
    }

    var risk: Risk = .clear
    var title = "Network device"
    var reason = "Only a web interface is open. Probably a router, printer or TV."

    if let keyword = cameraKeywords.first(where: { lowered.contains($0) }) {
        risk = .danger
        title = "Likely IP camera"
        reason = "Its response mentions “\(keyword)”."
    } else if hasStream {
        risk = .danger
        title = "Video streaming device"
        reason = "Port 554/8554 (RTSP) is open. This is the standard camera streaming port."
    } else if hasDVR {
        risk = .danger
        title = "Camera or DVR service"
        reason = "Open port is used by DVR and IP camera software."
    } else if ports.contains(8000) {
        risk = .caution
        title = "Unknown service"
        reason = "Port 8000 is common on camera SDKs. Identify this device."
    } else if ports.isEmpty {
        reason = "Responded on the network."
    }

    return NetDevice(id: ip, ip: ip, ports: ports, title: title, reason: reason, server: server, risk: risk)
}

func scanHost(_ ip: String) async -> NetDevice? {
    let ports: [UInt16] = [80, 554, 8080, 8554, 8000, 8899, 37777, 34567]
    var found: [(UInt16, ProbeResult)] = []
    await withTaskGroup(of: (UInt16, ProbeResult).self, returning: Void.self) { group in
        for p in ports {
            group.addTask {
                let r = await probe(host: ip, port: p, timeout: 1.5)
                return (p, r)
            }
        }
        for await item in group {
            if item.1.open {
                found.append(item)
            }
        }
    }
    if found.isEmpty { return nil }
    return classify(ip: ip, results: found)
}

func scanSubnet(prefix: String, skip: String, onUpdate: @escaping @Sendable (Double, NetDevice?) -> Void) async {
    let total = 254
    await withTaskGroup(of: NetDevice?.self, returning: Void.self) { group in
        var next = 1
        var inFlight = 0
        var done = 0
        while (next <= total || inFlight > 0) && !Task.isCancelled {
            while inFlight < 20 && next <= total {
                let ip = prefix + String(next)
                next += 1
                if ip == skip {
                    done += 1
                    continue
                }
                inFlight += 1
                group.addTask {
                    return await scanHost(ip)
                }
            }
            if inFlight == 0 { continue }
            if let result = await group.next() {
                inFlight -= 1
                done += 1
                onUpdate(Double(done) / Double(total), result)
            }
        }
        if Task.isCancelled {
            group.cancelAll()
        }
    }
}

func localIPv4() -> String? {
    var address: String? = nil
    var ifaddr: UnsafeMutablePointer<ifaddrs>? = nil
    guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
    defer { freeifaddrs(ifaddr) }
    var ptr: UnsafeMutablePointer<ifaddrs>? = first
    while let current = ptr {
        let iface = current.pointee
        if let addr = iface.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) {
            let name = String(cString: iface.ifa_name)
            if name == "en0" {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let result = getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
                if result == 0 {
                    address = String(cString: host)
                }
            }
        }
        ptr = iface.ifa_next
    }
    return address
}

final class NetworkScanner: ObservableObject {
    @Published var devices: [NetDevice] = []
    @Published var progress: Double = 0
    @Published var isScanning = false
    @Published var finished = false
    @Published var localIP: String? = nil
    @Published var error: String? = nil

    private var task: Task<Void, Never>? = nil
    private var scanID = 0

    func start() {
        guard !isScanning else { return }
        devices = []
        progress = 0
        finished = false
        error = nil
        guard let ip = localIPv4() else {
            error = "Connect to Wi-Fi to scan the network."
            return
        }
        let parts: [Substring] = ip.split(separator: ".")
        guard parts.count == 4 else {
            error = "Couldn't read the local network address."
            return
        }
        let prefix: String = parts[0...2].joined(separator: ".") + "."
        localIP = ip
        isScanning = true
        scanID += 1
        let id = scanID
        task = Task { [weak self] in
            await scanSubnet(prefix: prefix, skip: ip) { (value: Double, device: NetDevice?) in
                DispatchQueue.main.async {
                    self?.apply(id: id, progress: value, device: device)
                }
            }
            DispatchQueue.main.async {
                guard let self = self, self.scanID == id, self.isScanning else { return }
                self.isScanning = false
                self.finished = true
            }
        }
    }

    func stop() {
        task?.cancel()
        isScanning = false
    }

    private func apply(id: Int, progress value: Double, device: NetDevice?) {
        guard id == scanID else { return }
        withAnimation(.spring(duration: 0.35)) {
            progress = value
            if let device = device {
                devices.append(device)
                devices.sort { (a: NetDevice, b: NetDevice) -> Bool in
                    if a.risk != b.risk { return a.risk > b.risk }
                    return a.ip < b.ip
                }
            }
        }
    }
}
