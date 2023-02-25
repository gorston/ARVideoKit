//
//  RenderAR.swift
//  ARVideoKit
//
//  Created by Ahmed Bekhit on 1/7/18.
//  Copyright © 2018 Ahmed Fathit Bekhit. All rights reserved.
//

import ARKit
import Foundation

@available(iOS 13.0, *)
struct RenderAR {
    private var view: Any?
    private var renderEngine: SCNRenderer!
    var ARcontentMode: ARFrameMode!
    
    init(_ ARview: Any?, renderer: SCNRenderer, contentMode: ARFrameMode) {
        view = ARview
        renderEngine = renderer
        ARcontentMode = contentMode
    }
    
    let pixelsQueue = DispatchQueue(label: "com.ahmedbekhit.PixelsQueue", attributes: .concurrent)
    var time: CFTimeInterval { return CACurrentMediaTime() }
    var rawBuffer: CVPixelBuffer? {
        if let view = view as? ARSCNView {
            guard let rawBuffer = view.session.currentFrame?.capturedImage else { return nil }
            return rawBuffer
        } else if let view = view as? ARSKView {
            guard let rawBuffer = view.session.currentFrame?.capturedImage else { return nil }
            return rawBuffer
        } else if view is SCNView {
            return buffer?.recordBuffer
        }
        return nil
    }
    
    var bufferSize: CGSize? {
        guard let raw = rawBuffer else { return nil }
        var width = CVPixelBufferGetWidth(raw)
        var height = CVPixelBufferGetHeight(raw)
        
        if let contentMode = ARcontentMode {
            switch contentMode {
            case .auto:
                if UIScreen.main.isNotch {
                    width = Int(UIScreen.main.nativeBounds.width)
                    height = Int(UIScreen.main.nativeBounds.height)
                }
            case .aspectFit:
                width = CVPixelBufferGetWidth(raw)
                height = CVPixelBufferGetHeight(raw)
            case .aspectFill:
                width = Int(UIScreen.main.nativeBounds.width)
                height = Int(UIScreen.main.nativeBounds.height)
            case .viewAspectRatio where view is UIView:
                let bufferWidth = CVPixelBufferGetWidth(raw)
                let bufferHeight = CVPixelBufferGetHeight(raw)
                let viewSize = (view as! UIView).bounds.size
                let targetSize = AVMakeRect(aspectRatio: viewSize, insideRect: CGRect(x: 0, y: 0, width: bufferWidth, height: bufferHeight)).size
                width = Int(targetSize.width)
                height = Int(targetSize.height)
            default:
                if UIScreen.main.isNotch {
                    width = Int(UIScreen.main.nativeBounds.width)
                    height = Int(UIScreen.main.nativeBounds.height)
                }
            }
        }
        
        if width > height {
            return CGSize(width: height, height: width)
        } else {
            return CGSize(width: width, height: height)
        }
    }
    
    var bufferSizeFill: CGSize? {
        guard let raw = rawBuffer else { return nil }
        let width = CVPixelBufferGetWidth(raw)
        let height = CVPixelBufferGetHeight(raw)
        if width > height {
            return CGSize(width: height, height: width)
        } else {
            return CGSize(width: width, height: height)
        }
    }
    
    var buffer: RecordStreamBuffers? {
        if view is ARSCNView {
            guard let size = bufferSize else { return nil }
            // UIScreen.main.bounds.size
            var renderedStreamFrame: UIImage?
            var renderedRecordFrame: UIImage?

            pixelsQueue.sync {
                var snapshot = renderEngine.snapshot(atTime: time, with: size, antialiasingMode: .none)
                renderedStreamFrame = snapshot.rotate(by: -90, flip: false)
                renderedRecordFrame = snapshot
            }
            
            return RecordStreamBuffers(streamBuffer: renderedStreamFrame?.buffer, recordBuffer: renderedRecordFrame?.buffer)
        }
        return nil
    }
}

class RecordStreamBuffers{
    var recordBuffer: CVPixelBuffer?
    var streamBuffer : CVPixelBuffer?
    
    init( streamBuffer: CVPixelBuffer?, recordBuffer: CVPixelBuffer?) {
        self.recordBuffer = recordBuffer
        self.streamBuffer = streamBuffer
    }
}
