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
        case gettingWorldMap
        case segmenting
        case weighting
    }
    
    @IBOutlet var sceneView: ARSCNView!
    @IBOutlet weak var recognizeButton: UIButton!
    @IBOutlet weak var progressUIView: UIView!
    @IBOutlet weak var progressView: UIProgressView!
    @IBOutlet weak var statusLabel: UILabel!
    
    fileprivate var worldMaps: [ARWorldMap] = Array<ARWorldMap>()
    fileprivate var segmentInMessages: [Slimtest_SegmentInMessage] = Array<Slimtest_SegmentInMessage>()
    
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
        
        self.sessionId = ""
        
        self.worldMaps.removeAll()
        self.segmentInMessages.removeAll()
        
        self.statusLabel.text = String(format: "Mapping world...", self.attempts)
    }

    fileprivate var state: State! = State.stopped
    fileprivate let attempts: Int = 10
    fileprivate let interval: Int = 500
    fileprivate var finishedAttempts: Int = 0
    fileprivate let threshold: Int = 0
    fileprivate var sessionId: String = ""
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

    func distanceTo(to: CGPoint) -> Float? {
        let results = self.sceneView.hitTest(to, types: [.featurePoint])
        guard let result = results.first else { return Float(-1) }
        
        return Float(result.distance)
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

        guard let snapshot = uiimage.pngData() else {
            return false
        }
        
        var inMessage = Slimtest_SegmentInMessage();
        
        inMessage.photo = snapshot;
        
        self.segmentInMessages.append(inMessage);
        
        return true;
    }
    
    func measureDistances(outMessages: Slimtest_SegmentOutMessages) -> Array<Float> {
        var distances = Array<Float>()
        
        for j in 0..<outMessages.messages.count {
            self.sceneView.session.pause();
            
            let configuration = ARWorldTrackingConfiguration();

            configuration.initialWorldMap = self.worldMaps[j];
            
            self.sceneView.session.run(configuration)
            
            let pointsDistancesBetween = outMessages.messages[j].pointsDistancesBetween;
            
            for i in stride(from: 0, to: pointsDistancesBetween.count, by: 4) {
                var distance = Float(-1.0)
                
                let p1X = Double(pointsDistancesBetween[i])
                let p1Y = Double(pointsDistancesBetween[i + 1])
                let p2X = Double(pointsDistancesBetween[i + 2])
                let p2Y = Double(pointsDistancesBetween[i + 3])
                
                let htest1 = self.sceneView.hitTest(CGPoint(x: p1X, y: p1Y), types: [.featurePoint]).first
                let htest2 = self.sceneView.hitTest(CGPoint(x: p2X, y: p2Y), types: [.featurePoint]).first
                
                if (htest1 != nil && htest2 != nil) {
                    let distanceX = htest1!.worldTransform.columns.3.x - htest2!.worldTransform.columns.3.x
                    let distanceY = htest1!.worldTransform.columns.3.y - htest2!.worldTransform.columns.3.y
                    let distanceZ = htest1!.worldTransform.columns.3.z - htest2!.worldTransform.columns.3.z
                           
                    distance = sqrtf((distanceX * distanceX) + (distanceY * distanceY) + (distanceZ * distanceZ))
                }
                
                distances.append(distance)
            }
        }
        
        return distances;
    }
    
    func requestWeight(segmentOutMessages: Slimtest_SegmentOutMessages, distances: Array<Float>) {
        self.state = State.weighting
                
        var inMessage = Slimtest_WeightInMessage();
                
        inMessage.segmentOutMessages = segmentOutMessages
        inMessage.distancesBetween = distances
                
        let url = URL(string: String(format: "http://%@:7878/beslim.ai/weight?debug=1&session_id=%@", self.host, self.sessionId))
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
                    
            let outMessage = try? Slimtest_WeightOutMessage(serializedData: data)
            guard outMessage != nil else {
                return
            }
                    
            let productClass = outMessage!.productClass
            let weight = outMessage!.weight
                    
            DispatchQueue.main.async {
                self.statusLabel.text = "Recognized"
                
                self.progressView.setProgress(
                    Float(self.attempts + 3) / Float(self.attempts + 3), animated: true)
                
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
    
    func requestSegment() {
        var inMessages = Slimtest_SegmentInMessages();
                
        inMessages.messages = self.segmentInMessages
                
        let url = URL(
            string: String(format: "http://%@:7878/beslim.ai/segment?debug=1", self.host)
                + (self.sessionId == "" ? "" : "&session_id=" + self.sessionId)
        );
        
        var request = URLRequest(url: url!)
        request.httpMethod = "POST"
        request.setValue("application/x-protobuf", forHTTPHeaderField: "Content-Type")
        
        guard ((try? request.httpBody = inMessages.serializedData()) != nil) else {
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
                    
            let outMessages = try? Slimtest_SegmentOutMessages(serializedData: data)
            guard outMessages != nil else {
                return
            }
                    
            // TODO: rewrite - stopped task may overwrite session id!!!
            self.sessionId = outMessages!.sessionID
                
            DispatchQueue.main.async {
                let distances = self.measureDistances(outMessages: outMessages!)
                
                self.progressView.setProgress(
                    Float(self.attempts + 2) / Float(self.attempts + 3), animated: true)
                
                self.requestWeight(segmentOutMessages: outMessages!, distances: distances)
            }
        }
        
        task.resume()
    }
     
    // MARK: - ARSessionDelegate
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        if (state == State.mappingWorld) {
            let snapshotTime = Int(Date().timeIntervalSince1970 * 1000)
            if (frame.worldMappingStatus == .mapped && snapshotTime - lastSnapshotTime >= interval) {
                state = State.gettingWorldMap
                
                self.statusLabel.text = String(
                    format: "Making snapshot %d of %d...", self.finishedAttempts + 1, self.attempts)
                
                sceneView.session.getCurrentWorldMap {
                    (worldMap, error) in
                    
                    self.state = State.mappingWorld
                    
                    guard let worldMap = worldMap else {
                        return;
                    }
                    
                    if (!self.takeSnapshot(frame: frame)) {
                        return;
                    }
                    
                    self.worldMaps.append(worldMap)
                    
                    self.lastSnapshotTime = snapshotTime
                    
                    self.finishedAttempts += 1
                    
                    self.progressView.setProgress(
                        Float(self.finishedAttempts) / Float(self.attempts + 3), animated: true)
                    
                    if (self.finishedAttempts == self.attempts) {
                        self.state = State.segmenting;
                        
                        self.statusLabel.text = "Recognizing..."
                        
                        self.progressView.setProgress(
                            Float(self.attempts + 1) / Float(self.attempts + 3), animated: true)
                        
                        self.requestSegment();
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
