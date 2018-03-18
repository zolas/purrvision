//
//  MediaViewController.swift
//  PurrVision
//
//  Created by M on 2018-03-17.
//  Copyright © 2018 Black Magma Inc. All rights reserved.
//

import UIKit
import os.log
import CoreML
import AVFoundation
import Vision

enum ToolBarButtons: Int {
    case CameraButton
    case PhotoButton
    case SpaceButton
}

struct ToolBarButtonDataSource {
    var buttons: [ToolBarButtons]
}

class MediaViewController: UIViewController {
    
    private let vowels: [Character] = ["a", "e", "i", "o", "u"]
    private let imagePicker = UIImagePickerController()
    private let translationLabel = UILabel()
    private let imageView = UIImageView()
    private let toolBar = UIToolbar()
    private let toolBarButtons = ToolBarButtonDataSource(buttons: [.CameraButton, .SpaceButton, .PhotoButton])
    
    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private let captureQueue = DispatchQueue(label: "captureQueue")
    var visionRequests = [VNRequest]()

    private var previewView: UIView!

    var recognitionThreshold : Float = 0.25

    override func viewDidLoad() {
        super.viewDidLoad()
        setup()
    }
    
    private func setup() {
        setupToolbar()
        setupTranslationLabel()
        setupImageView()
        setupImagePicker()
        setupCamera()
    }
    
    private func setupToolbar() {
        // ToolBar
        toolBar.barStyle = .blackTranslucent
        toolBar.isTranslucent = true
        toolBar.backgroundColor = UIColor.blue
        toolBar.tintColor = UIColor.white
        toolBar.sizeToFit()
        var buttonArray = [UIBarButtonItem]()
        for buttonType in toolBarButtons.buttons {
            var toolBarButton: UIBarButtonItem?
            switch buttonType {
            case .CameraButton:
                toolBarButton = UIBarButtonItem(title: "Camera", style: .plain, target: self, action: #selector(self.cameraButtonTapped))
            case .PhotoButton:
                toolBarButton = UIBarButtonItem(title: "Photo", style: .plain, target: self, action: #selector(self.photoButtonTapped))
            case .SpaceButton:
                toolBarButton = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
            }
            
            if let toolBarButton = toolBarButton {
                buttonArray.append(toolBarButton)
            }
        }

        // Toolbar buttons
        toolBar.setItems(buttonArray, animated: false)
        toolBar.isUserInteractionEnabled = true
        view.addSubview(toolBar)
        
        // Toolbar constraints
        toolBar.translatesAutoresizingMaskIntoConstraints = false
        toolBar.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
        toolBar.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        toolBar.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
    }
    
    private func setupImageView() {
        imageView.contentMode = .scaleAspectFit
        view.addSubview(imageView)
        
        // ImageView constraints
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.topAnchor.constraint(equalTo: translationLabel.bottomAnchor).isActive = true
        imageView.bottomAnchor.constraint(equalTo: toolBar.topAnchor).isActive = true
        imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
    }
    
    private func setupTranslationLabel() {
        view.addSubview(translationLabel)
        translationLabel.backgroundColor = .lightGray
        translationLabel.text = NSLocalizedString("This application will translate a photo or frame to text", comment: "General.Translation.Default")
        translationLabel.textColor = .white
        translationLabel.numberOfLines = 0
        let translationLabelHeight:CGFloat = 150
        
        // ImageView constraints
        translationLabel.translatesAutoresizingMaskIntoConstraints = false
        translationLabel.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        translationLabel.heightAnchor.constraint(equalToConstant:translationLabelHeight ).isActive = true
        translationLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        translationLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
    }
    
    private func setupImagePicker() {
        imagePicker.delegate = self
        imagePicker.sourceType = .photoLibrary
        imagePicker.allowsEditing = false
    }
    
    private func setupCamera() {
        guard let camera = AVCaptureDevice.default(for: .video) else {
            // No camera available, only allow picking static images
            return
        }
        do {
            previewLayer = AVCaptureVideoPreviewLayer(session: session)
            previewView.layer.addSublayer(previewLayer)
            view.addSubview(previewView)
            previewView.translatesAutoresizingMaskIntoConstraints = false
            previewView.topAnchor.constraint(equalTo: translationLabel.bottomAnchor).isActive = true
            previewView.bottomAnchor.constraint(equalTo: toolBar.topAnchor).isActive = true
            previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
            previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true

            let cameraInput = try AVCaptureDeviceInput(device: camera)
            
            let videoOutput = AVCaptureVideoDataOutput()
            videoOutput.setSampleBufferDelegate(self, queue: captureQueue)
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            session.sessionPreset = .cif352x288
            
            session.addInput(cameraInput)
            session.addOutput(videoOutput)
            
            let conn = videoOutput.connection(with: .video)
            conn?.videoOrientation = .portrait
            
            session.startRunning()

            // set up the vision model
            guard let resNet50Model = try? VNCoreMLModel(for: Resnet50().model) else {
                fatalError("Could not load model")
            }
            // set up the request using our vision model
            let classificationRequest = VNCoreMLRequest(model: resNet50Model, completionHandler: handleClassifications)
            classificationRequest.imageCropAndScaleOption = .centerCrop
            visionRequests = [classificationRequest]
        } catch {
            fatalError(error.localizedDescription)
        }

    }
    
    func handleClassifications(request: VNRequest, error: Error?) {
        if let theError = error {
            print("Error: \(theError.localizedDescription)")
            return
        }
        guard let results = request.results as? [VNClassificationObservation],
            let topResult = results.first else {
                fatalError("unexpected result type from VNCoreMLRequest")
        }
        
        self.updateTranslation(text: topResult.identifier, confidence: topResult.confidence)
    }
    
    private func switchMediaInput(cameraInput: Bool) {
        guard let toolBarItems = toolBar.items else {
            os_log("No toolbar items found when switching media input.")
            return
        }
        for (index, button) in toolBarItems.enumerated() {
            guard (index < toolBarButtons.buttons.count) else {
                os_log("Toolbar items datasource contains less items than the toolbar.")
                return
            }
            if toolBarButtons.buttons[index] == .CameraButton {
                button.isEnabled = !cameraInput
            }
        }
        previewView?.isHidden = !cameraInput
        
        if cameraInput {
            session.startRunning()
        } else {
            session.stopRunning()
        }
    }
    
    @objc func cameraButtonTapped() {
        switchMediaInput(cameraInput: true)
    }
    
    @objc func photoButtonTapped() {
        switchMediaInput(cameraInput: false)
        displayImagePicker()
    }
    
    private func displayImagePicker() {
        present(imagePicker, animated: true, completion: nil)
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
}

extension MediaViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        connection.videoOrientation = .portrait
        
        var requestOptions:[VNImageOption: Any] = [:]
        
        if let cameraIntrinsicData = CMGetAttachment(sampleBuffer, kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix, nil) {
            requestOptions = [.cameraIntrinsics: cameraIntrinsicData]
        }
        
        // for orientation see kCGImagePropertyOrientation
        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .upMirrored, options: requestOptions)
        do {
            try imageRequestHandler.perform(self.visionRequests)
        } catch {
            print(error)
        }
    }
}

extension MediaViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String : Any]) {
        if let pickedImage = info[UIImagePickerControllerOriginalImage] as? UIImage {
            DispatchQueue.main.async {
                self.imageView.image = pickedImage
            }
            
            guard let ciImage = CIImage(image: pickedImage) else {
                fatalError("couldn't convert UIImage to CIImage")
            }
            
            detectScene(image: ciImage)
        }
        
        dismiss(animated: true, completion: nil)
    }
}

// Image Analysis
extension MediaViewController {
    func detectScene(image: CIImage) {
        translationLabel.text = "detecting scene..."
        
        guard let model = try? VNCoreMLModel(for: Resnet50().model) else {
            fatalError("can't load Resnet model")
        }
        
        let request = visionRequest(model: model)

        let handler = VNImageRequestHandler(ciImage: image)
        DispatchQueue.global(qos: .userInteractive).async {
            do {
                try handler.perform([request])
            } catch {
                print(error)
            }
        }
    }
    
    func visionRequest(model: VNCoreMLModel) -> VNRequest {
        // Create a Vision request with completion handler
        let request = VNCoreMLRequest(model: model) { [weak self] request, error in
            guard let results = request.results as? [VNClassificationObservation],
                let topResult = results.first else {
                    fatalError("unexpected result type from VNCoreMLRequest")
            }
            
            self?.updateTranslation(text: topResult.identifier, confidence: topResult.confidence)
        }
        return request
    }
    
    func updateTranslation(text: String, confidence: VNConfidence) {
        // Update UI on main queue
        let article = (self.vowels.contains(text.first!)) ? "an" : "a"
        DispatchQueue.main.async { [weak self] in
            self?.translationLabel.text = "\(Int(confidence * 100))% it's \(article) \(text)"
        }
    }
}
