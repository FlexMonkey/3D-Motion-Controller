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

class ViewController: UIViewController, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate, MCSessionDelegate, NSStreamDelegate
{
    let label = UILabel()

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
        }
        else
        {
            label.text = "iPhone"
            
            initialiseBrowsing()
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
        
        browser.invitePeer(peerID, toSession: session, withContext: nil, timeout: 10)
        
        NSTimer.scheduledTimerWithTimeInterval(1/30, target: self, selector: "timerHandler", userInfo: nil, repeats: true)
    }
    

    
    func startStream()
    {
        guard let streamTargetPeer = streamTargetPeer where outputStream == nil else
        {
            return
        }
        
        do
        {
            outputStream =  try session.startStreamWithName("MotionControllerStream", toPeer: streamTargetPeer)
      
            outputStream?.scheduleInRunLoop(NSRunLoop.mainRunLoop(), forMode: NSDefaultRunLoopMode)
            
            outputStream?.open()
        }
        catch
        {
            print("unable to strat stream!! \(error)")
        }
    }
    
    var foo:Float = 1
    
    func timerHandler()
    {
        startStream()
        
        guard let outputStream = outputStream else
        {
            print("no stream")
            return
        }
        
        if outputStream.hasSpaceAvailable
        {
            let attitude = MotionControllerAttitude(roll: foo + 0.33, pitch: foo + 0.66, yaw: foo + 0.99)
            
            self.label.text = "stream: \(attitude.roll) | \(attitude.pitch) | \(attitude.yaw)"
            
            outputStream.write(attitude.toBytes(), maxLength: 12)
            
            foo++
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
        print("\(UIDevice.currentDevice().userInterfaceIdiom.rawValue) didChangeState: \(state.rawValue)")
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
        if let inputStream = stream as? NSInputStream where eventCode == NSStreamEvent.HasBytesAvailable
        {
            var bytes = [UInt8](count:12, repeatedValue: 0)
            inputStream.read(&bytes, maxLength: 12)

            let foo = MotionControllerAttitude(fromBytes: bytes)
            
            self.label.text = "stream: \(foo.roll) | \(foo.pitch) | \(foo.yaw)"
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
        label.frame = view.bounds
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