//
//  ViewController.swift
//  3D Motion Controller
//
//  Created by SIMON_NON_ADMIN on 29/08/2015.
//  Copyright © 2015 Simon Gladman. All rights reserved.
//
// Thanks to http://www.ralfebert.de/tutorials/ios-swift-multipeer-connectivity/
// Thanks to https://www.objc.io/issues/18-games/multipeer-connectivity-for-games/
// Thanks to http://nshipster.com/multipeer-connectivity/

import UIKit
import MultipeerConnectivity
import CoreMotion
import SceneKit

class ViewController: UIViewController, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate, MCSessionDelegate, NSStreamDelegate
{
    let label = UILabel()

    var displayLink: CADisplayLink?
    
    let serviceType = "motion-control"
    let peerID = MCPeerID(displayName: UIDevice.currentDevice().name)
    
    var serviceAdvertiser : MCNearbyServiceAdvertiser!
    var serviceBrowser : MCNearbyServiceBrowser!
    
    lazy var session : MCSession =
    {
        let session = MCSession(peer: self.peerID, securityIdentity: nil, encryptionPreference: MCEncryptionPreference.None)
        session.delegate = self
        return session
    }()
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        label.textAlignment = NSTextAlignment.Center
        
        view.addSubview(label)
        
        if UIDevice.currentDevice().userInterfaceIdiom == UIUserInterfaceIdiom.Pad
        {
            label.text = "iPad"
            
            initialiseAdvertising()
            setupSceneKit()
        }
        else
        {
            label.text = "iPhone"
            
            initialiseBrowsing()
            setupMotionControl()
        }

    }
    
    // MARK: Simple SceneKit for iPad

    var sceneKitView: SCNView?
    var geometryNode: SCNNode?
    
    func setupSceneKit()
    {
        sceneKitView = SCNView()
        
        if let sceneKitView = sceneKitView
        {
            view.addSubview(sceneKitView)
            
            sceneKitView.bounds = view.frame.insetBy(dx: 50, dy: 50)
            
            sceneKitView.scene = SCNScene()
            
            let cameraNode = SCNNode()
            cameraNode.position = SCNVector3(x: 0, y: 0, z: 20)
            
            let camera = SCNCamera()
            camera.xFov = 40
            camera.yFov = 40
            
            cameraNode.camera = camera
            sceneKitView.scene!.rootNode.addChildNode(cameraNode)
            
            geometryNode = SCNNode(geometry: SCNBox(width: 5, height: 5, length: 5, chamferRadius: 0.5))
            geometryNode!.position = SCNVector3(x: 0, y: 0, z: 0)
            sceneKitView.scene!.rootNode.addChildNode(geometryNode!)
            
            let omniLight = SCNLight()
            omniLight.type = SCNLightTypeOmni
            omniLight.color = UIColor(white: 1.0, alpha: 1.0)
            let omniLightNode = SCNNode()
            omniLightNode.light = omniLight
            omniLightNode.position = SCNVector3(x: -5, y: 8, z: 10)
            
            sceneKitView.scene!.rootNode.addChildNode(omniLightNode)
        }
    }
    
    // MARK: Motion Control for iPhone
    
    var initialAttitude: MotionControllerAttitude?
    var attitude: MotionControllerAttitude?
    let motionManager = CMMotionManager()
    
    func setupMotionControl()
    {
        guard motionManager.gyroAvailable else
        {
            fatalError("CMMotionManager not available.")
        }
        
        let queue = NSOperationQueue.mainQueue
        
        motionManager.deviceMotionUpdateInterval = 1 / 30
        
        motionManager.startDeviceMotionUpdatesToQueue(queue())
        {
            (deviceMotionData: CMDeviceMotion?, error: NSError?) in
            
            if let deviceMotionData = deviceMotionData
            {
                if (self.initialAttitude == nil)
                {
                    self.initialAttitude = MotionControllerAttitude(roll: deviceMotionData.attitude.roll,
                        pitch: deviceMotionData.attitude.pitch,
                        yaw: deviceMotionData.attitude.yaw)
                }
              
                self.attitude = MotionControllerAttitude(roll: self.initialAttitude!.roll - Float(deviceMotionData.attitude.roll),
                    pitch: self.initialAttitude!.pitch - Float(deviceMotionData.attitude.pitch),
                    yaw: self.initialAttitude!.yaw - Float(deviceMotionData.attitude.yaw))
            }
        }
    }
    
    // MARK: MCNearbyServiceBrowserDelegate (iPhone is browser)
    
    var streamTargetPeer: MCPeerID?
    var outputStream: NSOutputStream?
    
    func initialiseBrowsing()
    {
        serviceBrowser = MCNearbyServiceBrowser(peer: peerID, serviceType: serviceType)
        
        serviceBrowser.delegate = self
        serviceBrowser.startBrowsingForPeers()
    }
    
    func browser(browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?)
    {
        label.text = "Found Peer! \(peerID)"
 
        streamTargetPeer = peerID
        
        browser.invitePeer(peerID, toSession: session, withContext: nil, timeout: 120)
        
        displayLink = CADisplayLink(target: self, selector: Selector("step"))
        displayLink?.addToRunLoop(NSRunLoop.mainRunLoop(), forMode: NSDefaultRunLoopMode)
        
        //NSTimer.scheduledTimerWithTimeInterval(1/30, target: self, selector: "step", userInfo: nil, repeats: true)
    }
    

    func startStream()
    {
        guard let streamTargetPeer = streamTargetPeer where outputStream == nil else
        {
            return
        }
        
        do
        {
            outputStream =  try session.startStreamWithName("SimonStream", toPeer: streamTargetPeer)
      
            outputStream?.scheduleInRunLoop(NSRunLoop.mainRunLoop(), forMode: NSDefaultRunLoopMode)
            
            outputStream?.open()
        }
        catch
        {
            print("unable to start stream!! \(error)")
        }
    }
  
    func step()
    {
        startStream()
        
        guard let outputStream = outputStream else
        {
            print("no stream")
            return
        }
        
        if let attitude = attitude where outputStream.hasSpaceAvailable
        {
            self.label.text = "stream: \(attitude.roll.radiansToDegrees()) | \(attitude.pitch.radiansToDegrees()) | \(attitude.yaw.radiansToDegrees())"
            
            outputStream.write(attitude.toBytes(), maxLength: 12)
        }
        else
        {
            print("no space availale")
        }
    }

    func browser(browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID)
    {
        label.text = "Lost Peer!"
    }
    
    // MARK: MCNearbyServiceAdvertiserDelegate (iPad is advertiser)
    
    func initialiseAdvertising()
    {
        serviceAdvertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: serviceType)
        
        serviceAdvertiser.delegate = self
        serviceAdvertiser.startAdvertisingPeer()
    }
    
    func advertiser(advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: NSData?, invitationHandler: (Bool, MCSession) -> Void)
    {
        invitationHandler(true, self.session)
    }
    
    // MARK: MCSessionDelegate
    
    func session(session: MCSession, peer peerID: MCPeerID, didChangeState state: MCSessionState)
    {
        let stateName:String
        
        switch state
        {
        case MCSessionState.Connected:
            stateName = "connected"
        case MCSessionState.Connecting:
            stateName = "connecting"
        case MCSessionState.NotConnected:
            stateName = "not connected"
        }
        
        let deviceName:String
        
        switch UIDevice.currentDevice().userInterfaceIdiom
        {
        case UIUserInterfaceIdiom.Pad:
            deviceName = "iPad"
        case UIUserInterfaceIdiom.Phone:
            deviceName = "iPhone"
        case UIUserInterfaceIdiom.Unspecified:
            deviceName = "Unspecified"
        }
        
        print("\(deviceName) didChangeState: \(stateName)")
        
        dispatch_async(dispatch_get_main_queue())
        {
            self.label.text = stateName
        }
    }
    
    func session(session: MCSession, didReceiveData data: NSData, fromPeer peerID: MCPeerID)
    {
    }
    
    func session(_: MCSession, didReceiveStream stream: NSInputStream, withName streamName: String, fromPeer peerID: MCPeerID)
    {
        stream.scheduleInRunLoop(NSRunLoop.mainRunLoop(), forMode: NSDefaultRunLoopMode)
        
        stream.delegate = self
        
        stream.open()
    }
    
    func stream(stream: NSStream, handleEvent eventCode: NSStreamEvent)
    {
        print("stream in....!")
        
        if let inputStream = stream as? NSInputStream where eventCode == NSStreamEvent.HasBytesAvailable
        {
            var bytes = [UInt8](count:12, repeatedValue: 0)
            inputStream.read(&bytes, maxLength: 12)

            let streamedAttitude = MotionControllerAttitude(fromBytes: bytes)
            
            dispatch_async(dispatch_get_main_queue())
            {
                self.label.text = "stream: \(streamedAttitude.roll.radiansToDegrees()) | \(streamedAttitude.pitch.radiansToDegrees()) | \(streamedAttitude.yaw.radiansToDegrees())"
                
                self.geometryNode?.eulerAngles = SCNVector3(x: -streamedAttitude.pitch, y: streamedAttitude.yaw, z: streamedAttitude.roll)
            
            }
        }
    }
    
    func session(session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, atURL localURL: NSURL, withError error: NSError?)
    {
    }
    
    func session(session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, withProgress progress: NSProgress)
    {
    }
    
    // MARK: Layout
    
    override func viewDidLayoutSubviews()
    {
        label.frame = CGRect(x: 0, y: topLayoutGuide.length, width: view.frame.width, height: label.intrinsicContentSize().height)
        
        sceneKitView?.frame = view.frame.insetBy(dx: 50, dy: 50)
    }
    
}

extension Float
{
    func radiansToDegrees() -> Float
    {
        return round(self * (180 / Float(M_PI)))
    }
}

struct MotionControllerAttitude
{
    let roll: Float
    let pitch: Float
    let yaw: Float
    
    init(roll: Float, pitch: Float, yaw: Float)
    {
        self.roll = roll
        self.pitch = pitch
        self.yaw = yaw
    }
    
    init(roll: Double, pitch: Double, yaw: Double)
    {
        self.roll = Float(roll)
        self.pitch = Float(pitch)
        self.yaw = Float(yaw)
    }
    
    init(fromBytes: [UInt8])
    {
        roll = fromByteArray(Array(fromBytes[0...3]), Float.self)
        pitch = fromByteArray(Array(fromBytes[4...7]), Float.self)
        yaw = fromByteArray(Array(fromBytes[8...11]), Float.self)
    }
    
    func toBytes() -> [UInt8]
    {
        let composite = [roll, pitch, yaw]
        
        return composite.flatMap(){toByteArray($0)}
    }
}


// http://stackoverflow.com/questions/26953591/how-to-convert-a-double-into-a-byte-array-in-swift

func fromByteArray<T>(value: [UInt8], _: T.Type) -> T {
    return value.withUnsafeBufferPointer {
        return UnsafePointer<T>($0.baseAddress).memory
    }
}

func toByteArray<T>(var value: T) -> [UInt8] {
    return withUnsafePointer(&value) {
        Array(UnsafeBufferPointer(start: UnsafePointer<UInt8>($0), count: sizeof(T)))
    }
}