//
//  ViewController.swift
//  FacialEmotionDetection
//
//  Created by Joshua Newnham on 26/02/2018.
//  Copyright © 2018 PacktPub. All rights reserved.
//

import UIKit
import Vision
import AVFoundation

class ViewController: UIViewController {

    /**
     Reference to our views CapturePreviewView (Camera stream)
    */
    @IBOutlet weak var previewView: CapturePreviewView!
    
    /**
     Reference to our view responsible for displaying the current users emotion
    */
    @IBOutlet weak var visualizerView: EmotionVisualizerView!
    
    /**
     Utility class that encapsulates setting up and tearing down the video capture; we'll start recording
     and assign the ViewController as a delegate to receive captured images from the video stream.
     */
    let videoCapture : VideoCapture = VideoCapture()
    
    /**
     Utility class encapsulating methods for data pre-processing
    */
    let imageProcessor : ImageProcessor = ImageProcessor()
    
    /**
     An image analysis request that uses a Core ML model to process images; the processing is determined by the associated MLModel.
     */
    var request: VNCoreMLRequest!
    
    let model = ExpressionRecognitionModel()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        videoCapture.delegate = self
        
        videoCapture.asyncInit { (success) in
            if success{
                // Assign the capture session instance being previewed
                (self.previewView.layer as! AVCaptureVideoPreviewLayer).session = self.videoCapture.captureSession
                // You use the videoGravity property to influence how content is viewed relative to the layer bounds;
                // in this case setting it to full the screen while respecting the aspect ratio.
                (self.previewView.layer as! AVCaptureVideoPreviewLayer).videoGravity = AVLayerVideoGravity.resizeAspectFill
                
                if self.initVision(){
                    self.videoCapture.startCapturing()
                } else{
                    fatalError("Unable to init Vision")
                }
            } else{
                fatalError("Failed to init VideoCapture")
            }
        }
        
        imageProcessor.delegate = self
    }
    
    /**
     Initilise the MLModel's Vision Reuqest; return true is successful otherwise false.
     */
    private func initVision() -> Bool{
        // Try and create a container for our CoreML model which will be used with Vision requests
        guard let visionModel = try? VNCoreMLModel(for:model.model) else{ return false }
        
        // Create the CoreML request
        self.request = VNCoreMLRequest(model: visionModel, completionHandler:onVisionRequestComplete)
        self.request.imageCropAndScaleOption = .centerCrop
        
        return true
    }
}

// MARK: - VideoCaptureDelegate

extension ViewController : VideoCaptureDelegate{
    
    func onFrameCaptured(videoCapture: VideoCapture, pixelBuffer:CVPixelBuffer?, timestamp:CMTime){
        // Unwrap the parameter pixxelBuffer; exit early if nil
        guard let pixelBuffer = pixelBuffer else{ return }
        
        // Get orientation
        guard let exifOrientation = CGImagePropertyOrientation(
            rawValue: exifOrientationFromDeviceOrientation()) else { return }
        
        // extract faces
        self.imageProcessor.getFaces(pixelBuffer: pixelBuffer, imageOrientation: exifOrientation)
    }
    
    /**
     Code taken from Apple's WWDC 2017 samples
     */
    private func exifOrientationFromDeviceOrientation() -> UInt32 {
        enum DeviceOrientation: UInt32 {
            case top0ColLeft = 1
            case top0ColRight = 2
            case bottom0ColRight = 3
            case bottom0ColLeft = 4
            case left0ColTop = 5
            case right0ColTop = 6
            case right0ColBottom = 7
            case left0ColBottom = 8
        }
        var exifOrientation: DeviceOrientation
        
        switch UIDevice.current.orientation {
        case .portraitUpsideDown:
            exifOrientation = .left0ColBottom
        case .landscapeLeft:
            exifOrientation = self.videoCapture.cameraPostion == .front ? .bottom0ColRight : .top0ColLeft
        case .landscapeRight:
            exifOrientation = self.videoCapture.cameraPostion == .front ? .top0ColLeft : .bottom0ColRight
        default:
            exifOrientation = .right0ColTop
        }
        return exifOrientation.rawValue
    }
}

// MARK: - VisionRequest callback

extension ViewController{
    
    func onVisionRequestComplete(request: VNRequest, error: Error?) {
        /*
         A request can be given a hander which is called once
         the inference has been performed; the resutls is of type VNRequest
         and includes a results variable including ... the results of the
         inference - if no error has occured.
         
         The results, in our case, are observations (array of VNClassificationObservation); this datatype is returned by VNCoreMLRequests that are using a model performing
         classification (like our expression recognition model).
         */
        guard let observations = request.results as? [VNClassificationObservation] else{ return }
        
        /*
         Each observation consists of a label and confidence level;
         observations are sorted by confidence - let's map these to a dictionary
         and pass them to the visualizer.
         */
        let emotions = observations.reduce([String:Float]()) { (result, observation) -> [String:Float] in
            var result = result
            result[observation.identifier] = observation.confidence
            return result
        }
        
        DispatchQueue.main.sync {
            visualizerView.update(labelConference: emotions)
        }
    }
}

// MARK: - VideoCaptureDelegate

extension ViewController : ImageProcessorDelegate{
    
    func onImageProcessorCompleted(status: Int, faces:[CIImage]?){
        guard let faces = faces else{ return }
        
        guard let exifOrientation = CGImagePropertyOrientation(
            rawValue: exifOrientationFromDeviceOrientation()) else { return }
        
        DispatchQueue.global(qos: .background).async {
            for face in faces{
                // Create the Handler which will be responsible for the processing of this image.
                let handler = VNImageRequestHandler(
                    ciImage: face,
                    orientation: exifOrientation,
                    options: [:])
                try? handler.perform([self.request])
            }
        }
    }
    
}
