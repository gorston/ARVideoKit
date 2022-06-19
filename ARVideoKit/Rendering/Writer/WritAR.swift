//
//  WritAR.swift
//  AR Video
//
//  Created by Ahmed Bekhit on 10/19/17.
//  Copyright © 2017 Ahmed Fathi Bekhit. All rights reserved.
//

import AVFoundation
import CoreImage
import UIKit

@available(iOS 14.0, *)
class WritAR: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    private var assetWriter: AVAssetWriter!
    private var videoInput: AVAssetWriterInput!
    private var audioInput: AVAssetWriterInput!
    private var session: AVCaptureSession!
    
    private var pixelBufferInput: AVAssetWriterInputPixelBufferAdaptor!
    private var videoOutputSettings: Dictionary<String, AnyObject>!
    private var audioSettings: [String: Any]?

    let audioBufferQueue = DispatchQueue(label: "com.ahmedbekhit.AudioBufferQueue")

    private var isRecording: Bool = false
    let streamController = globalStreamController
    weak var delegate: RecordARDelegate?
    var videoInputOrientation: ARVideoOrientation = .auto
    var recordStreamSettrings: RecordStreamSettings = .streamOnly

    init(output: URL, width: Int, height: Int, adjustForSharing: Bool, audioEnabled: Bool, orientaions:[ARInputViewOrientation], queue: DispatchQueue, allowMix: Bool) {
        super.init()
        do {
            assetWriter = try AVAssetWriter(outputURL: output, fileType: AVFileType.mp4)
        } catch {
            // FIXME: handle when failed to allocate AVAssetWriter.
            return
        }
        guard let streamController = streamController else {
            return
        }
        streamController.config()
        if audioEnabled {
            if allowMix {
                let audioOptions: AVAudioSession.CategoryOptions = [.mixWithOthers , .allowBluetooth, .defaultToSpeaker, .interruptSpokenAudioAndMixWithOthers]
                try? AVAudioSession.sharedInstance().setCategory(AVAudioSession.Category.playAndRecord, mode: AVAudioSession.Mode.spokenAudio, options: audioOptions)
                try? AVAudioSession.sharedInstance().setActive(true)
            }
            AVAudioSession.sharedInstance().requestRecordPermission({ permitted in
                if permitted {
                    self.prepareAudioDevice(with: queue)
                }
            })
        }
        
        //HEVC file format only supports A10 Fusion Chip or higher.
        //to support HEVC, make sure to check if the device is iPhone 7 or higher
        videoOutputSettings = [
            AVVideoCodecKey: AVVideoCodecType.h264 as AnyObject,
            AVVideoWidthKey: width as AnyObject,
            AVVideoHeightKey: height as AnyObject
        ]
        
        let attributes: [String: Bool] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoOutputSettings)

        videoInput.expectsMediaDataInRealTime = true
        pixelBufferInput = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: nil)
        
        if recordStreamSettrings != .videoOnly {
            streamController.startPublish()
        }
      
        
        var angleEnabled: Bool {
            for v in orientaions {
                if UIDevice.current.orientation.rawValue == v.rawValue {
                    return true
                }
            }
            return false
        }
        
        var recentAngle: CGFloat = 0
        var rotationAngle: CGFloat = 0
        switch UIDevice.current.orientation {
        case .landscapeLeft:
            rotationAngle = -90
            recentAngle = -90
        case .landscapeRight:
            rotationAngle = 90
            recentAngle = 90
        case .faceUp, .faceDown, .portraitUpsideDown:
            rotationAngle = recentAngle
        default:
            rotationAngle = 0
            recentAngle = 0
        }
        
        if !angleEnabled {
            rotationAngle = 0
        }
        
        var t = CGAffineTransform.identity

        switch videoInputOrientation {
        case .auto:
            t = t.rotated(by: ((rotationAngle*CGFloat.pi) / 180))
        case .alwaysPortrait:
            t = t.rotated(by: 0)
        case .alwaysLandscape:
            if rotationAngle == 90 || rotationAngle == -90 {
                t = t.rotated(by: ((rotationAngle * CGFloat.pi) / 180))
            } else {
                t = t.rotated(by: ((-90 * CGFloat.pi) / 180))
            }
        }
        
        videoInput.transform = t
        
        if assetWriter.canAdd(videoInput) {
            assetWriter.add(videoInput)
        } else {
            delegate?.recorder(didFailRecording: assetWriter.error, and: "An error occurred while adding video input.")
            isWritingWithoutError = false
        }
        assetWriter.shouldOptimizeForNetworkUse = adjustForSharing
    }
    
    func prepareAudioDevice(with queue: DispatchQueue) {
        let device: AVCaptureDevice = AVCaptureDevice.default(for: .audio)!
        var audioDeviceInput: AVCaptureDeviceInput?
        do {
            audioDeviceInput = try AVCaptureDeviceInput(device: device)
        } catch {
            audioDeviceInput = nil
        }
        
        let audioDataOutput = AVCaptureAudioDataOutput()
        audioDataOutput.setSampleBufferDelegate(self, queue: queue)

        session = AVCaptureSession()
        session.sessionPreset = .medium
        session.usesApplicationAudioSession = true
        session.automaticallyConfiguresApplicationAudioSession = false
        
        if session.canAddInput(audioDeviceInput!) {
            session.addInput(audioDeviceInput!)
        }
        if session.canAddOutput(audioDataOutput) {
            session.addOutput(audioDataOutput)
        }
        

        audioSettings = audioDataOutput.recommendedAudioSettingsForAssetWriter(writingTo: .m4v) as? [String: Any]
        
        audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioInput.expectsMediaDataInRealTime = true
        
        audioBufferQueue.async {
            self.session?.startRunning()
        }
        
        if assetWriter.canAdd(audioInput) {
            assetWriter.add(audioInput)
        }
    }
    
    var startingVideoTime: CMTime?
    var isWritingWithoutError: Bool?
    var currentDuration: TimeInterval = 0 // Seconds
    
    func insert(pixel buffer: CVPixelBuffer, with intervals: CFTimeInterval) {
        let time: CMTime = CMTime(seconds: intervals, preferredTimescale: 1000000)
        insert(pixel: buffer, with: time)
    }
    
    func insert(pixel buffer: CVPixelBuffer, with time: CMTime) {
        if assetWriter.status == .unknown {
            guard startingVideoTime == nil else {
                isWritingWithoutError = false
                return
            }
            startingVideoTime = time
            if assetWriter.startWriting() {
                assetWriter.startSession(atSourceTime: startingVideoTime!)
                currentDuration = 0
                isRecording = true
                isWritingWithoutError = true
            } else {
                delegate?.recorder(didFailRecording: assetWriter.error, and: "An error occurred while starting the video session.")
                currentDuration = 0
                isRecording = false
                isWritingWithoutError = false
            }
        } else if assetWriter.status == .failed {
            delegate?.recorder(didFailRecording: assetWriter.error, and: "Video session failed while recording.")
            logAR.message("An error occurred while recording the video, status: \(assetWriter.status.rawValue), error: \(assetWriter.error!.localizedDescription)")
            currentDuration = 0
            isRecording = false
            isWritingWithoutError = false
            return
        }
        
        if videoInput.isReadyForMoreMediaData {
            append(pixel: buffer, with: time)
            currentDuration = time.seconds - startingVideoTime!.seconds
            isRecording = true
            isWritingWithoutError = true
            delegate?.recorder?(didUpdateRecording: currentDuration)
        }
    }

   public var audioEnabled = true
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
       
    
        
        if let input = audioInput, audioEnabled {
            audioBufferQueue.async { [weak self] in
                if let isRecording = self?.isRecording,
                    let session = self?.session,
                    input.isReadyForMoreMediaData && isRecording
                        && session.isRunning {
                    
                    switch self?.recordStreamSettrings {
                    case .videoOnly:
                        input.append(sampleBuffer)
                    case .streamOnly:
                        guard let streamController = self?.streamController else {
                            return
                        }
                        streamController.rtmpStream.appendSampleBuffer(sampleBuffer, withType: .audio)
                    case .both:
                        guard let streamController = self?.streamController else {
                            return
                        }
                        input.append(sampleBuffer)
                        streamController.rtmpStream.appendSampleBuffer(sampleBuffer, withType: .audio)
                    case .none:
                        return
                    }
                   
                    
                   
                    
                }
            }
        }
    }
    
    func pause() {
        isRecording = false
    }
    
    func end(writing finished: @escaping () -> Void) {
        
        if recordStreamSettrings != .videoOnly {
            guard let streamController = streamController else {
                return
            }
            streamController.stopPublish()
        }
      
        if let session = session {
            if session.isRunning {
                session.stopRunning()
            }
        }
        if recordStreamSettrings != .streamOnly {
            if assetWriter.status == .writing {
                isRecording = false
                assetWriter.finishWriting(completionHandler: finished)
            }
        }
       
    }
    
    func cancel() {
        if let session = session {
            if session.isRunning {
                session.stopRunning()
            }
        }
        isRecording = false
        assetWriter.cancelWriting()
    }
}

@available(iOS 14.0, *)
private extension WritAR {
    func append(pixel buffer: CVPixelBuffer, with time: CMTime) {
        
        switch self.recordStreamSettrings {
        case .videoOnly:
            pixelBufferInput.append(buffer, withPresentationTime: time)
        case .streamOnly:
            guard let streamController = self.streamController else {
                return
            }
//            guard let newBuffer = rotate(buffer) else {
//                return
//            }
            
            guard  let newSample = createVideoSampleBufferWithPixelBuffer(buffer, presentationTime: time) else {
                return
            }
            
            streamController.rtmpStream.orientation = .landscapeRight
            
            
            streamController.rtmpStream.appendSampleBuffer(newSample, withType: .video)
        case .both:
            guard let streamController = self.streamController else {
                return
            }
            pixelBufferInput.append(buffer, withPresentationTime: time)
            guard let newBuffer = rotate(buffer) else {
                return
            }
            
            guard  let newSample = createVideoSampleBufferWithPixelBuffer(newBuffer, presentationTime: time) else {
                return
            }
            
            streamController.rtmpStream.orientation = .landscapeRight
            
            
            streamController.rtmpStream.appendSampleBuffer(newSample, withType: .video)
       
        }
    }
    
    func rotate(_ sampleBuffer: CVPixelBuffer) -> CVPixelBuffer? {
           
            var newPixelBuffer: CVPixelBuffer?
            let error = CVPixelBufferCreate(kCFAllocatorDefault,
                                            CVPixelBufferGetHeight(sampleBuffer),
                                            CVPixelBufferGetWidth(sampleBuffer),
                                            kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                                            nil,
                                            &newPixelBuffer)
            guard error == kCVReturnSuccess else {
                return nil
            }
        let ciImage = CIImage(cvPixelBuffer: sampleBuffer).oriented(.left)
       
            let context = CIContext(options: nil)
       
//        let resizeFilter = CIFilter(name:"CILanczosScaleTransform")!
//        // Desired output size
//        let targetSize = CGSize(width:1920, height:1080)
//
//        // Compute scale and corrective aspect ratio
//        let scale = targetSize.height / (ciImage.extent.height)
//        let aspectRatio = targetSize.width/((ciImage.extent.width) * scale)
//
//        // Apply resizing
//        resizeFilter.setValue(ciImage, forKey: kCIInputImageKey)
//        resizeFilter.setValue(scale, forKey: kCIInputScaleKey)
//        resizeFilter.setValue(aspectRatio, forKey: kCIInputAspectRatioKey)
//        let outputImage = resizeFilter.outputImage
//
        
            context.render(ciImage, to: newPixelBuffer!)
            return newPixelBuffer
        }
    
    
    private func createVideoSampleBufferWithPixelBuffer(_ pixelBuffer: CVPixelBuffer,presentationTime: CMTime) -> CMSampleBuffer? {
        var sampleBuffer: CMSampleBuffer?
        var formatDescription: CMFormatDescription? = nil
        
    CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescriptionOut: &formatDescription)
        var timingInfo = CMSampleTimingInfo(duration: .invalid,  presentationTimeStamp: presentationTime, decodeTimeStamp: .invalid)
       
        let err = CMSampleBufferCreateForImageBuffer(allocator: kCFAllocatorDefault,
                                                     imageBuffer: pixelBuffer,
                                                     dataReady: true,
                                                     makeDataReadyCallback: nil,
                                                     refcon: nil,
                                                     formatDescription: formatDescription!,
                                                     sampleTiming: &timingInfo,
                                                     sampleBufferOut: &sampleBuffer)
        
        
        if sampleBuffer == nil {
            print("Error: Sample buffer creation failed (error code: \(err))")
        }
       
       
       
        return sampleBuffer
    }
}

//Simple Logging to show logs only while debugging.
class logAR {
    class func message(_ message: String) {
        #if DEBUG
            print("ARVideoKit @ \(Date().timeIntervalSince1970):- \(message)")
        #endif
    }
    
    class func remove(from path: URL?) {
        if let file = path?.path {
            let manager = FileManager.default
            if manager.fileExists(atPath: file) {
                do{
                    try manager.removeItem(atPath: file)
                    self.message("Successfuly deleted media file from cached after exporting to Camera Roll.")
                } catch let error {
                    self.message("An error occurred while deleting cached media: \(error)")
                }
            }
        }
    }
}
