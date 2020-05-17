//
//  ViewController.swift
//  SlimTest
//
//  Created by Anton on 2/27/20.
//  Copyright © 2020 SlimTest. All rights reserved.
//

import UIKit
import SceneKit
import ARKit
import VideoToolbox

class ViewController: UIViewController, ARSCNViewDelegate, ARSessionDelegate {
    
    enum State {
        case stopped
        case waitingForRestart
        case mappingWorld
        case takingSnapshot
        case weighting
        case recognized
    }
    
    @IBOutlet var sceneView: ARSCNView!
    @IBOutlet weak var recognizeButton: UIButton!
    @IBOutlet weak var progressUIView: UIView!
    @IBOutlet weak var progressView: UIProgressView!
    @IBOutlet weak var statusLabel: UILabel!
    
    fileprivate var snapshots: Beslim_Ai_WeightInMessage = Beslim_Ai_WeightInMessage()
    
    @IBAction func recognize(_ sender: Any) {
        if state == State.recognized {
            self.restart()
        } else if state == State.stopped {
            recognizeButton.setTitle("Stop", for: UIControl.State.normal)
            
            progressUIView.isHidden = false
            
            sceneView.session.pause()
            
            resumeSession()
            
            state = State.waitingForRestart
        } else {
            restart()
        }
    }
    
    func restart() {
        self.state = State.stopped
        
        self.progressUIView.isHidden = true
        self.progressView.setProgress(0.0, animated: false)
        
        self.recognizeButton.setTitle("Recognize", for: UIControl.State.normal)
        
        self.finishedAttempts = 0
        
        self.lastCameraPosition = nil;
        
        self.snapshots.snapshots.removeAll()
        
        self.statusLabel.text = String(format: "Mapping world...", self.attempts)
    }

    fileprivate var state: State! = State.stopped
    fileprivate let attempts: Int = 40
    fileprivate let gridStep: Int = 10
    fileprivate let minMovement: Float = 0.02;
    fileprivate var lastCameraPosition: simd_float4x4?
    fileprivate var finishedAttempts: Int = 0
    fileprivate let host = "193.106.92.67"
    //fileprivate let host = "95.216.150.30"
    
    fileprivate var text: SCNText!
    
    
    
    //fileprivate let debugOptions: ARSCNDebugOptions = [ARSCNDebugOptions.showFeaturePoints]
    fileprivate let debugOptions: ARSCNDebugOptions = []
    
    override var supportedInterfaceOrientations : UIInterfaceOrientationMask {
        if self.state != State.stopped {
            if UIApplication.shared.statusBarOrientation == UIInterfaceOrientation.landscapeLeft {
                return UIInterfaceOrientationMask.landscapeLeft;
            } else if UIApplication.shared.statusBarOrientation == UIInterfaceOrientation.landscapeRight {
                return UIInterfaceOrientationMask.landscapeRight
            } else if UIApplication.shared.statusBarOrientation == UIInterfaceOrientation.portrait {
                return UIInterfaceOrientationMask.portrait
            } else if UIApplication.shared.statusBarOrientation == UIInterfaceOrientation.portraitUpsideDown {
                return UIInterfaceOrientationMask.portraitUpsideDown
            }
        }
            
        if UIDevice.current.userInterfaceIdiom == .phone {
            return .allButUpsideDown
        } else {
            return .all
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set the view's delegate
        sceneView.delegate = self
        sceneView.session.delegate = self
        
        sceneView.debugOptions = self.debugOptions
        
        // Show statistics such as fps and timing information
        sceneView.showsStatistics = false
        
        restart();
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        resumeSession();
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Pause the view's session
        sceneView.session.pause()
    }
    
    func resumeSession() {
        let configuration = ARWorldTrackingConfiguration()
        
        // Restart the view's session
        self.sceneView.session.run(configuration, options: [ARSession.RunOptions.resetTracking, ARSession.RunOptions.removeExistingAnchors])
        
        //self.sceneView.debugOptions = self.debugOptions
    }
  
    func takeSnapshot(
        frame: ARFrame,
        cameraX: Float,
        cameraY: Float,
        cameraZ: Float,
        cameraUpX: Float,
        cameraUpY: Float,
        cameraUpZ: Float,
        cameraFov: Float
    ) -> Bool {
        let orientation = UIApplication.shared.statusBarOrientation

        let vSize = sceneView.bounds.size
        
        var ciimage = CIImage(cvPixelBuffer: frame.capturedImage)
        
        let transform = frame.displayTransform(for: orientation, viewportSize: vSize).inverted()
        ciimage = ciimage.transformed(by: transform)

        let cameraImage = sceneView.snapshot().cgImage
        
        let c = CGContext(data: nil, width: Int(vSize.width), height: Int(vSize.height), bitsPerComponent: cameraImage!.bitsPerComponent, bytesPerRow: cameraImage!.bytesPerRow, space: cameraImage!.colorSpace!, bitmapInfo: cameraImage!.bitmapInfo.rawValue)
        
        c!.draw(cameraImage!, in: CGRect(origin: CGPoint.zero, size: vSize))
        
        guard let ccImage = c!.makeImage() else {
            return false
        }
        
        let uiimage = UIImage(cgImage: ccImage);

        guard let photo = uiimage.jpegData(compressionQuality: 0.1) else {
            return false
        }
        
        var snapshot = Beslim_Ai_Snapshot()
        
        snapshot.cameraX = cameraX
        snapshot.cameraY = cameraY
        snapshot.cameraZ = cameraZ
        
        snapshot.cameraUpX = cameraUpX
        snapshot.cameraUpY = cameraUpY
        snapshot.cameraUpZ = cameraUpZ
        
        snapshot.cameraFov = cameraFov
        
        let centerX = Int(vSize.width / 2)
        let centerY = Int(vSize.height / 2)
        
        var htest = self.sceneView.hitTest(
            CGPoint(x: centerX, y: centerY), types: [.featurePoint]
        ).first
        
        if (htest == nil) {
            return false
        }
        
        snapshot.lookAtX = htest!.worldTransform.columns.3.x
        snapshot.lookAtY = htest!.worldTransform.columns.3.y
        snapshot.lookAtZ = htest!.worldTransform.columns.3.z
        
        let startX = centerX % gridStep
        let startY = centerY % gridStep
        for y in stride(from: startY, to: Int(vSize.height), by: gridStep) {
            var row = Beslim_Ai_Row()
            
            for x in stride(from: startX, to: Int(vSize.width), by: gridStep) {
                htest = self.sceneView.hitTest(CGPoint(x: x, y: y), types: [.featurePoint]).first
    
                if (htest == nil) {
                    return false
                }
                
                var coords = Beslim_Ai_Coords()
                
                coords.vx = Int32(x);
                coords.vy = Int32(y);
                
                coords.x = htest!.worldTransform.columns.3.x
                coords.y = htest!.worldTransform.columns.3.y
                coords.z = htest!.worldTransform.columns.3.z
                
                row.row.append(coords)
            }
            
            snapshot.grid.append(row)
        }
        
        snapshot.photo = photo
        
        self.snapshots.snapshots.append(snapshot);
        
        return true;
    }
    
    func requestWeight() {
        let url = URL(string: String(format: "http://%@:7878/beslim.ai/weight?debug=1", self.host))
        var request = URLRequest(url: url!)
        request.httpMethod = "POST"
        request.setValue("application/x-protobuf", forHTTPHeaderField: "Content-Type")
        guard ((try? request.httpBody = snapshots.serializedData()) != nil) else {
            return
        }
                
        let task = URLSession.shared.dataTask(with: request) {
            (data, response, error) in
            
            guard error == nil else {
                return
            }

            guard let data = data else {
                return
            }
                    
            let outMessage = try? Beslim_Ai_WeightOutMessage(serializedData: data)
            guard outMessage != nil else {
                return
            }
                    
            let productClass = outMessage!.productClass
            let weight = outMessage!.weight
                    
            DispatchQueue.main.async {
                if productClass == "Unknown" {
                    self.statusLabel.text = "Unknown"
                } else {
                    self.statusLabel.text = String(format: "%@ (%.0fg)", productClass, weight)
                }
                
                self.recognizeButton.setTitle("OK", for: UIControl.State.normal)
                
                self.state = State.recognized
            }
        }
                
        task.resume()
    }
     
    // MARK: - ARSessionDelegate
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        if (state == State.waitingForRestart && frame.worldMappingStatus != .mapped) {
            state = State.mappingWorld;
        }
        
        if (state == State.mappingWorld) {
            var distance = minMovement * minMovement
            let cameraPosition = frame.camera.transform
            if (lastCameraPosition != nil) {
                distance = 0.0
                for i in 0..<3 {
                    distance += (lastCameraPosition![3, i] - cameraPosition[3, i])
                        * (lastCameraPosition![3, i] - cameraPosition[3, i])
                }
            }
            
            if (frame.worldMappingStatus == .mapped && distance >= minMovement * minMovement) {
                state = State.takingSnapshot
                
                self.statusLabel.text = "Taking snapshots..."
                
                let imageResolution = frame.camera.imageResolution
                let intrinsics = frame.camera.intrinsics
                let xFovDegrees
                    = 2.0 * atan(Float(imageResolution.width) / (2.0 * intrinsics[0, 0])) * 180.0 / Float.pi
                let yFovDegrees
                    = 2.0 * atan(Float(imageResolution.height) / (2.0 * intrinsics[1, 1])) * 180.0 / Float.pi
                let fovDegrees = (xFovDegrees + yFovDegrees) / 2.0
                
                let result = self.takeSnapshot(
                    frame: frame,
                    cameraX: cameraPosition[3, 0],
                    cameraY: cameraPosition[3, 1],
                    cameraZ: cameraPosition[3, 2],
                    cameraUpX: cameraPosition[0, 0],
                    cameraUpY: cameraPosition[0, 1],
                    cameraUpZ: cameraPosition[0, 2],
                    cameraFov: fovDegrees
                )
            
                self.state = State.mappingWorld
                
                if (!result) {
                    return;
                }
                                        
                self.lastCameraPosition = cameraPosition
                    
                self.finishedAttempts += 1
                    
                self.progressView.setProgress(
                    Float(self.finishedAttempts) / Float(self.attempts), animated: true)
                    
                if (self.finishedAttempts == self.attempts) {
                    self.state = State.weighting
                    
                    self.statusLabel.text = "Weighting..."
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.requestWeight()
                    }
                }
            }
        }
    }
    
    // MARK: - ARSCNViewDelegate
    
/*
    // Override to create and configure nodes for anchors added to the view's session.
    func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        let node = SCNNode()
     
        return node
    }
*/
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        // Present an error message to the user
        
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        // Inform the user that the session has been interrupted, for example, by presenting an overlay
        
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        // Reset tracking and/or remove existing anchors if consistent tracking is required
        
    }
}
