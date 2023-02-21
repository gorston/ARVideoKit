import AVFoundation
import Combine
import HaishinKit
import Logboard
import PhotosUI
import SwiftUI
import VideoToolbox

//@available(iOS 14.0, *)
//final class ExampleRecorderDelegate: DefaultAVRecorderDelegate {
//    static let `default` = ExampleRecorderDelegate()
//
//    override func didFinishWriting(_ recorder: AVRecorder) {
//        guard let writer: AVAssetWriter = recorder.writer else {
//            return
//        }
//        PHPhotoLibrary.shared().performChanges({ () in
//            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: writer.outputURL)
//        }, completionHandler: { _, error in
//            do {
//                try FileManager.default.removeItem(at: writer.outputURL)
//            } catch {
//                print(error)
//            }
//        })
//    }
//}

@available(iOS 14.0, *)
public final class StreamController: ObservableObject {
    let maxRetryCount: Int = 2
    
    let uri: String
    let streamKey: String
    
    init(url: String, streamKey: String) {
        self.uri = url
        self.streamKey = streamKey
    }
    
    @Published public var rtmpConnection = RTMPConnection()
    @Published public var rtmpStream: RTMPStream!
    private var sharedObject: RTMPSharedObject!
    private var currentEffect: VideoEffect?
    @Published var currentPosition: AVCaptureDevice.Position = .back
    private var retryCount: Int = 0
    @Published var published: Bool = false
    @Published var zoomLevel: CGFloat = 1.0
    @Published var videoRate: CGFloat = 160.0
    @Published var audioRate: CGFloat = 32.0
    @Published var fps: String = "FPS"
    private var nc = NotificationCenter.default
    
    var subscriptions = Set<AnyCancellable>()
    
    var frameRate: String = "30.0" {
        willSet {
            rtmpStream.captureSettings[.fps] = Float(newValue)
            objectWillChange.send()
        }
    }
    
    var videoEffectData = ["None", "Monochrome", "Pronoma"]

    var frameRateData = ["15.0", "30.0", "60.0"]
    
    var bitrate = 3000


    
    public func config() {
        rtmpStream = RTMPStream(connection: rtmpConnection)
        rtmpStream.orientation = .portrait
        rtmpStream.captureSettings = [
            .sessionPreset: AVCaptureSession.Preset.hd1920x1080,

            // .preferredVideoStabilizationMode: AVCaptureVideoStabilizationMode.auto
        ]
        rtmpStream.videoSettings = [
            .width: 1920,
            .height: 1080,
            .profileLevel: kVTProfileLevel_H264_High_AutoLevel,
            .bitrate: bitrate * 1000,
        ]
//        rtmpStream.mixer.recorder.delegate = ExampleRecorderDelegate.shared
        
        nc.publisher(for: UIDevice.orientationDidChangeNotification, object: nil)
            .sink { [weak self] _ in
                guard let orientation = DeviceUtil.videoOrientation(by: UIDevice.current.orientation), let self = self else {
                    return
                }
              
                self.rtmpStream.orientation = orientation
                
//                var newBitrate : UInt32 = 0
//                let oldBitrate = self.rtmpStream.videoSettings[.bitrate] as! UInt32
//                let currBitsOut = self.rtmpConnection.currentBytesOutPerSecond * 8
//

//                    if(self.rtmpStream.currentFPS < 28 ||
//                       currBitsOut < UInt32(Double(self.bitrate) * 0.9)){
//
//                        newBitrate = UInt32(Double(currBitsOut) * 0.9)
//                    }
//
//
//                    if(self.rtmpStream.currentFPS <= 25){
//                        newBitrate = UInt32(Double(oldBitrate) * 0.8)
//
//                    }else if(oldBitrate < self.bitrate){
//                        newBitrate = oldBitrate + UInt32(Double(self.bitrate) * 0.1)
//
//                        if(newBitrate > self.bitrate){
//                            newBitrate = UInt32(self.bitrate);
//                        }
//                    }
//
//
//                if(newBitrate > 0){
//                    self.rtmpStream.videoSettings[.bitrate] = newBitrate
//
//                }
            }
            .store(in: &subscriptions)
        
        checkDeviceAuthorization()
    }
    
    func checkDeviceAuthorization() {
        let requiredAccessLevel: PHAccessLevel = .readWrite
        PHPhotoLibrary.requestAuthorization(for: requiredAccessLevel) { _ in
        }
    }
    
    func registerForPublishEvent() {
        rtmpStream.publisher(for: \.currentFPS)
            .sink { [weak self] currentFPS in
                guard let self = self else { return }
                
                DispatchQueue.main.async {
                    self.fps = self.published == true ? "\(currentFPS)" : "FPS"
                }
            }
            .store(in: &subscriptions)
        
        nc.publisher(for: AVAudioSession.interruptionNotification, object: nil)
            .sink { _ in
            }
            .store(in: &subscriptions)
        
        nc.publisher(for: AVAudioSession.routeChangeNotification, object: nil)
            .sink { _ in
            }
            .store(in: &subscriptions)
    }
    
    func unregisterForPublishEvent() {
        rtmpStream.close()
    }
    
    public func startPublish() {
        rtmpConnection.addEventListener(.rtmpStatus, selector: #selector(rtmpStatusHandler), observer: self)
        rtmpConnection.addEventListener(.ioError, selector: #selector(rtmpErrorHandler), observer: self)
        rtmpConnection.connect(uri)
    }
    
    public func stopPublish() {
//        UIApplication.shared.isIdleTimerDisabled = false
        rtmpConnection.close()
        rtmpConnection.removeEventListener(.rtmpStatus, selector: #selector(rtmpStatusHandler), observer: self)
        rtmpConnection.removeEventListener(.ioError, selector: #selector(rtmpErrorHandler), observer: self)
    }
    
    func toggleTorch() {
        rtmpStream.torch.toggle()
    }
    
    func pausePublish() {
        rtmpStream.paused.toggle()
    }
    
    func changeZoomLevel(level: CGFloat) {
        rtmpStream.setZoomFactor(level, ramping: true, withRate: 5.0)
    }
    
    func changeVideoRate(level: CGFloat) {
        rtmpStream.videoSettings[.bitrate] = level * 1000
    }
    
    func changeAudioRate(level: CGFloat) {
        rtmpStream.audioSettings[.bitrate] = level * 1000
    }
    
    @objc
    private func rtmpStatusHandler(_ notification: Notification) {
        let e = Event.from(notification)
        guard let data: ASObject = e.data as? ASObject, let code: String = data["code"] as? String else {
            return
        }
        print(code)
        switch code {
        case RTMPConnection.Code.connectSuccess.rawValue:
            retryCount = 0
            rtmpStream.publish(streamKey)
        // sharedObject!.connect(rtmpConnection)
        case RTMPConnection.Code.connectFailed.rawValue, RTMPConnection.Code.connectClosed.rawValue:
            guard retryCount <= maxRetryCount else {
                return
            }
            Thread.sleep(forTimeInterval: pow(2.0, Double(retryCount)))
            rtmpConnection.connect(uri)
            retryCount += 1
        default:
            break
        }
    }
    
    @objc
    private func rtmpErrorHandler(_ notification: Notification) {
        print("zalupaHappens")
        rtmpConnection.connect(uri)
    }
}
