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
    @IBOutlet var sceneView: ARSCNView!
    @IBOutlet weak var recognizeButton: UIButton!
    @IBOutlet weak var progressUIView: UIView!
    @IBOutlet weak var progressView: UIProgressView!
    @IBOutlet weak var statusLabel: UILabel!
    
    @IBAction func recognize(_ sender: Any) {
        if state == State.stopped {
            recognizeButton.setTitle("Stop", for: UIControl.State.normal)
            
            progressView.setProgress(0.0, animated: false)
            progressUIView.isHidden = false
            
            state = State.gatheringPoints
            
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
        
        self.sessionId = ""
        
        self.segmentOutMessages.removeAll()
        self.distances.removeAll()
        
        self.statusLabel.text = String(format: "Recognition 1 of %d...", self.attempts)
    }
    
    enum State {
        case stopped
        case gatheringPoints
        case waitingForServer
        case weighting
    }

    fileprivate var state: State! = State.stopped
    fileprivate let attempts: Int = 3
    fileprivate var finishedAttempts: Int = 0
    fileprivate let threshold: Int = 0
    fileprivate var sessionId: String = ""
    
    fileprivate var text: SCNText!
    fileprivate var textNode: SCNNode!
    fileprivate var distance: Float!
    //fileprivate var className: String!
    //fileprivate var coordinates: [Int32]!
    fileprivate var isClassifying: Bool!
    
    fileprivate var segmentOutMessages: [Slimtest_SegmentOutMessage] = Array<Slimtest_SegmentOutMessage>()
    fileprivate var distances: [Float] = Array<Float>()
    
    //fileprivate let debugOptions: ARSCNDebugOptions = [ARSCNDebugOptions.showFeaturePoints]
    fileprivate let debugOptions: ARSCNDebugOptions = []
    
    //fileprivate var state: UIAlertController!
    
    override var supportedInterfaceOrientations : UIInterfaceOrientationMask {
        if self.state == State.waitingForServer {
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
        
        
        text = SCNText(string: "", extrusionDepth: 0.1)
        text.font = .systemFont(ofSize: 5)
        text.firstMaterial?.diffuse.contents = UIColor.blue
        text.alignmentMode  = CATextLayerAlignmentMode.center.rawValue
        text.truncationMode = CATextLayerTruncationMode.middle.rawValue
        text.firstMaterial?.isDoubleSided = true
        
        let textWrapperNode = SCNNode(geometry: text)
        textWrapperNode.eulerAngles = SCNVector3Make(0, .pi, 0)
        textWrapperNode.scale = SCNVector3(1/500.0, 1/500.0, 1/500.0)
        
        textNode = SCNNode()
        textNode.addChildNode(textWrapperNode)
        let constraint = SCNLookAtConstraint(target: sceneView.pointOfView)
        constraint.isGimbalLockEnabled = true
        textNode.constraints = [constraint]
        sceneView.scene.rootNode.addChildNode(textNode)
        
        distance = Float()
        
        //state = UIAlertController(title: nil, message: "Waiting...", preferredStyle: .alert)
        
        isClassifying = false
        
        statusLabel.text = String(format: "Recognition 1 of %d...", attempts)
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

        // Detect horizontal planes in the scene
        //configuration.planeDetection = .horizontal
        
        // Restart the view's session
        self.sceneView.session.run(configuration, options: [ARSession.RunOptions.resetTracking, ARSession.RunOptions.removeExistingAnchors])
        
        //self.sceneView.debugOptions = self.debugOptions
        
        self.isClassifying = false;
    }
  
    // MARK: - ARSessionDelegate
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        if (state == State.gatheringPoints) {
            if ((frame.rawFeaturePoints?.points.count ?? 0) >= threshold && frame.worldMappingStatus == .mapped) {
                state = State.waitingForServer
                
                //sceneView.debugOptions = []
                
                sceneView.session.pause()
                
                let orientation = UIApplication.shared.statusBarOrientation
                let viewportSize = sceneView.snapshot().size
                let viewSize = sceneView.bounds.size
                //let vSize = view.bounds.size
                let vSize = sceneView.bounds.size
                
                var ciimage = CIImage(cvPixelBuffer: frame.capturedImage)

                let imageSize = ciimage.extent.size
                
                let transform = frame.displayTransform(for: orientation, viewportSize: vSize).inverted()
                ciimage = ciimage.transformed(by: transform)

                let context = CIContext(options: nil)
                //guard let cameraImage = context.createCGImage(ciimage, from: ciimage.extent) else { return }

                let cameraImage = sceneView.snapshot().cgImage
                
                let c = CGContext(data: nil, width: Int(vSize.width), height: Int(vSize.height), bitsPerComponent: cameraImage!.bitsPerComponent, bytesPerRow: cameraImage!.bytesPerRow, space: cameraImage!.colorSpace!, bitmapInfo: cameraImage!.bitmapInfo.rawValue)
                
                c!.draw(cameraImage!, in: CGRect(origin: CGPoint.zero, size: vSize))
                
                guard let ccImage = c!.makeImage() else { return }
                
                let uiimage = UIImage(cgImage: ccImage);

                
                guard let data = uiimage.pngData() else {
                    return;
                }
                
//                guard let data = sceneView.snapshot().pngData() else {
//                    return
//                }
                
                var inMessage = Slimtest_SegmentInMessage();
                
                inMessage.photo = data;
                
                let url = URL(string: String(format: "http://95.216.150.30:7878/beslim.ai/segment?debug=1&attempt=%d", self.finishedAttempts) + (self.sessionId == "" ? "" : "&session_id=" + self.sessionId))
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
                        
                        let outMessage = try? Slimtest_SegmentOutMessage(serializedData: data)
                        guard outMessage != nil else {
                            return
                        }
                        
                    let pointsDistancesBetween = outMessage!.pointsDistancesBetween
                        
                    // TODO: rewrite - stopped task may overwrite session id!!!
                    self.sessionId = outMessage!.sessionID
                    
                        DispatchQueue.main.async {
                                var retry = false
                                var distances = Array<Float>()
                                for i in stride(from: 0, to: pointsDistancesBetween.count, by: 4) {
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
                                               
                                        let distance = sqrtf((distanceX * distanceX) + (distanceY * distanceY) + (distanceZ * distanceZ))
                                        
                                        distances.append(distance)
                                    } else {
                                        retry = true
                                        
                                        break
                                    }
                                }
                            
                                if (!retry) {
                                    self.segmentOutMessages.append(outMessage!)
                                    self.distances += distances
                                    
                                    self.finishedAttempts += 1
                                self.progressView.setProgress(Float(self.finishedAttempts) / Float(self.attempts), animated: true)
                                }
                            
                            if (self.finishedAttempts == self.attempts) {
                                self.state = State.weighting
                                
                                var inMessage = Slimtest_WeightInMessage();
                                
                                inMessage.segmentOutMessages = self.segmentOutMessages
                                inMessage.distancesBetween = self.distances
                                
                                let url = URL(string: String(format: "http://95.216.150.30:7878/beslim.ai/weight?debug=1&session_id=%@", self.sessionId))
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
                                        self.restart()
                                        
                                        var text = String(format: "Product: %@", productClass)
                                        
                                        if productClass != "Unknown" {
                                            text += String(format: "\nEstimated weight: %.0fg", weight)
                                        }
                                        
                                        let alert = UIAlertController(title: "Recognition result", message: text, preferredStyle: .alert)

                                        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))

                                        self.present(alert, animated: true)
                                    }
                                }
                                
                                task.resume()
                            } else {
                                self.state = State.gatheringPoints
                                
                                self.statusLabel.text = String(format: "Recognition %d of %d...", self.finishedAttempts + 1, self.attempts)
                            }
                            
                            self.resumeSession()
                        }
                    }
                    
                    task.resume()
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
