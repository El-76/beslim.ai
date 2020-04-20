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
        case mappingWorld
        case takingSnapshot
        case weighting
    }
    
    @IBOutlet var sceneView: ARSCNView!
    @IBOutlet weak var recognizeButton: UIButton!
    @IBOutlet weak var progressUIView: UIView!
    @IBOutlet weak var progressView: UIProgressView!
    @IBOutlet weak var statusLabel: UILabel!
    
    fileprivate var snapshots: [Beslim_Ai_Snapshot] = Array<Beslim_Ai_Snapshot>()
    
    @IBAction func recognize(_ sender: Any) {
        if state == State.stopped {
            recognizeButton.setTitle("Stop", for: UIControl.State.normal)
            
            progressView.setProgress(0.0, animated: false)
            progressUIView.isHidden = false
            
            state = State.mappingWorld
            
            sceneView.session.pause()
            
            resumeSession()
        } else {
            restart()
        }
    }
    
    func restart() {
        self.state = State.stopped
        
        self.progressUIView.isHidden = true
        
        self.recognizeButton.setTitle("Recognize", for: UIControl.State.normal)
        
        self.finishedAttempts = 0
        
        self.lastSnapshotTime = 0
        
        self.snapshots.removeAll()
        
        self.statusLabel.text = String(format: "Mapping world...", self.attempts)
    }

    fileprivate var state: State! = State.stopped
    fileprivate let attempts: Int = 10
    fileprivate let gridStep: Int = 10
    fileprivate let interval: Int = 500
    fileprivate var finishedAttempts: Int = 0
    fileprivate let host = "193.106.92.67"
    //fileprivate let host = "95.216.150.30"
    
    fileprivate var text: SCNText!
    
    fileprivate var lastSnapshotTime: Int!
    
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
        
        self.sceneView.debugOptions = self.debugOptions
    }
  
    func takeSnapshot(frame: ARFrame) -> Bool {
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

        //guard let photo = uiimage.pngData() else {
        //    return false
        //}

        guard let photo = uiimage.jpegData(compressionQuality: 0.5) else {
            return false
        }
        
        var grid = Array<Beslim_Ai_Coords>()
        
        let startX = Int(vSize.width / 2) % gridStep
        let startY = Int(vSize.height / 2) % gridStep
        for x in stride(from: startX, to: Int(vSize.width), by: gridStep) {
            for y in stride(from: startY, to: Int(vSize.height), by: gridStep) {
                let htest = self.sceneView.hitTest(CGPoint(x: x, y: y), types: [.featurePoint]).first
    
                if (htest != nil) {
                    var coords = Beslim_Ai_Coords()
                    
                    coords.vx = Int32(x);
                    coords.vy = Int32(y);
                    
                    coords.x = htest!.worldTransform.columns.3.x
                    coords.y = htest!.worldTransform.columns.3.y
                    coords.z = htest!.worldTransform.columns.3.z
                    
                    grid.append(coords)
                }
            }
        }
        
        var snapshot = Beslim_Ai_Snapshot()
        
        snapshot.photo = photo
        snapshot.grid = grid
        
        self.snapshots.append(snapshot);
        
        return true;
    }
    
    func requestWeight() {
        self.state = State.weighting
                
        var inMessage = Beslim_Ai_WeightInMessage()
                
        inMessage.snapshots = self.snapshots
                
        let url = URL(string: String(format: "http://%@:7878/beslim.ai/weight?debug=1", self.host))
        var request = URLRequest(url: url!)
        request.httpMethod = "POST"
        request.setValue("application/x-protobuf", forHTTPHeaderField: "Content-Type")
        guard ((try? request.httpBody = inMessage.serializedData()) != nil) else {
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
                self.statusLabel.text = "Recognized"
                
                self.progressView.setProgress(
                    Float(self.attempts + 2) / Float(self.attempts + 2), animated: true)
                
                self.restart()
                        
                var text = String(format: "Product: %@", productClass)
                        
                if productClass != "Unknown" {
                    text += String(format: "\nEstimated weight: %.0fg", weight)
                }
                        
                let alert = UIAlertController(
                    title: "Recognition result", message: text, preferredStyle: .alert)

                alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))

                self.present(alert, animated: true)
            }
        }
                
        task.resume()
    }
     
    // MARK: - ARSessionDelegate
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        if (state == State.mappingWorld) {
            let snapshotTime = Int(Date().timeIntervalSince1970 * 1000)
            if (frame.worldMappingStatus == .mapped && snapshotTime - lastSnapshotTime >= interval) {
                state = State.takingSnapshot
                
                self.statusLabel.text = String(
                    format: "Taking snapshot %d of %d...", self.finishedAttempts + 1, self.attempts)
                
                let result = self.takeSnapshot(frame: frame)
            
                self.state = State.mappingWorld
                
                if (!result) {
                    return;
                }
                                        
                self.lastSnapshotTime = snapshotTime
                    
                self.finishedAttempts += 1
                    
                self.progressView.setProgress(
                    Float(self.finishedAttempts) / Float(self.attempts + 2), animated: true)
                    
                if (self.finishedAttempts == self.attempts) {
                    self.state = State.weighting;
                    
                    self.statusLabel.text = "Weighting..."
                    
                    self.progressView.setProgress(
                        Float(self.attempts + 1) / Float(self.attempts + 2), animated: true)
                    
                    self.requestWeight();
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
