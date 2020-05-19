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
        cameraUpZ: Float
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
        
        let centerVX = Int(vSize.width / 2)
        let centerVY = Int(vSize.height / 2)
        
        var centerTopX = Float(0.0)
        var centerTopY = Float(0.0)
        var centerTopZ = Float(0.0)
        
        var centerBottomX = Float(0.0)
        var centerBottomY = Float(0.0)
        var centerBottomZ = Float(0.0)
        
        let startX = centerVX % gridStep
        let startY = centerVY % gridStep
        for y in stride(from: startY, to: Int(vSize.height), by: gridStep) {
            var row = Beslim_Ai_Row()
            
            for x in stride(from: startX, to: Int(vSize.width), by: gridStep) {
                let htest = self.sceneView.hitTest(CGPoint(x: x, y: y), types: [.featurePoint]).first
    
                if (htest == nil) {
                    return false
                }
                
                var coords = Beslim_Ai_Coords()
                
                coords.vx = Int32(x);
                coords.vy = Int32(y);
                
                coords.x = htest!.worldTransform.columns.3.x
                coords.y = htest!.worldTransform.columns.3.y
                coords.z = htest!.worldTransform.columns.3.z
                
                if (x == centerVX && y == centerVY) {
                    snapshot.lookAtX = coords.x
                    snapshot.lookAtY = coords.y
                    snapshot.lookAtZ = coords.z
                }
                
                if (x == centerVX) {
                    if (y == startY) {
                        centerTopX = coords.x - cameraX
                        centerTopY = coords.y - cameraY
                        centerTopZ = coords.z - cameraZ
                    } else {
                        centerBottomX = coords.x - cameraX
                        centerBottomY = coords.y - cameraY
                        centerBottomZ = coords.z - cameraZ
                    }
                }
                
                row.row.append(coords)
            }
            
            snapshot.grid.append(row)
        }
        
        let dotProductY = (
            centerBottomX * centerTopX + centerBottomY * centerTopY + centerBottomZ * centerTopZ
        )
        let normBottom = sqrt(
            centerBottomX * centerBottomX + centerBottomY * centerBottomY + centerBottomZ * centerBottomZ
        )
        let normTop = sqrt(
            centerTopX * centerTopX + centerTopY * centerTopY + centerTopZ * centerTopZ
        )
        snapshot.cameraFov = acos(dotProductY / (normBottom * normTop)) * 180.0 / Float.pi
        
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
                
                var cameraUpX = Float(0.0)
                var cameraUpY = Float(0.0)
                var cameraUpZ = Float(0.0)
                if UIApplication.shared.statusBarOrientation == UIInterfaceOrientation.landscapeLeft {
                    cameraUpX = -cameraPosition[1, 0]
                    cameraUpY = -cameraPosition[1, 1]
                    cameraUpZ = -cameraPosition[1, 2]
                } else if UIApplication.shared.statusBarOrientation == UIInterfaceOrientation.landscapeRight {
                    cameraUpX = cameraPosition[1, 0]
                    cameraUpY = cameraPosition[1, 1]
                    cameraUpZ = cameraPosition[1, 2]
                } else if UIApplication.shared.statusBarOrientation == UIInterfaceOrientation.portrait {
                    cameraUpX = -cameraPosition[0, 0]
                    cameraUpY = -cameraPosition[0, 1]
                    cameraUpZ = -cameraPosition[0, 2]
                } else if UIApplication.shared.statusBarOrientation == UIInterfaceOrientation.portraitUpsideDown {
                    cameraUpX = cameraPosition[0, 0]
                    cameraUpY = cameraPosition[0, 1]
                    cameraUpZ = cameraPosition[0, 2]
                }
                
                let result = self.takeSnapshot(
                    frame: frame,
                    cameraX: cameraPosition[3, 0],
                    cameraY: cameraPosition[3, 1],
                    cameraZ: cameraPosition[3, 2],
                    cameraUpX: cameraUpX,
                    cameraUpY: cameraUpY,
                    cameraUpZ: cameraUpZ
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
