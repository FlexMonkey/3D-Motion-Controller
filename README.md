# 3D-Motion-Controller
Using MultipeerConnectivity and CoreMotion to allow an iPhone to act as a 3D mouse for an iPad app

Companion project to this blog post: http://flexmonkey.blogspot.co.uk/2015/08/using-iphone-as-3d-mouse-with-multipeer.html

My recent experiment with CoreMotion, CoreMotion Controlled 3D Sketching on an iPhone with Swift, got me wondering if it would be possible to use an iPhone as a 3D mouse to control another application on a separate device. It turns out that with Apple's Multipeer Connectivity framework, it's not only possible, it's pretty awesome too!

The Multipeer Connectivity framework provides peer to peer communication between iOS devices over Wi-Fi and Bluetooth. As well as allowing devices to send discrete bundles of information, it also supports streaming which is what I need to allow my iPhone to transmit a continuous stream of data describing its attitude (roll, pitch and yaw) in 3D space.

I won't go in the the finer details of the framework, these are explained beautifully in the three main articles I used to get me up to speed:

* [iOS & Swift Tutorial: Multipeer Connectivity by Ralf Ebert](http://www.ralfebert.de/tutorials/ios-swift-multipeer-connectivity/)
* [Multipeer Connectivity in Games at objc](https://www.objc.io/issues/18-games/multipeer-connectivity-for-games/)
* [Multipeer Connectivity by NSHipster](http://nshipster.com/multipeer-connectivity/)

My single codebase does the job of both the iPad "Rotating Cube" app which displays a cube floating in space and the iPhone "3D Mouse" app which controls the 3D rotation of the cube. As this is more of a proof-of-concept project rather than a piece of production code, everything is in a single view controller, this isn't good architecture, but when rapidly moving between the two "modes", it was super quick to work in.
##The iPad "Rotating Cube App"

Apps using Multipeer Connectivity can either advertise a service or browse for a service. In my project, the Rotating Cube App takes the role of the advertiser so my view controller implements the MCNearbyServiceAdvertiserDelegate protocol. After I start advertising:

```swift
    func initialiseAdvertising()
    {
        serviceAdvertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: serviceType)
        
        serviceAdvertiser.delegate = self
        serviceAdvertiser.startAdvertisingPeer()

    }
```

...the protocol's advertiser() method is invoked when it receives an invitation from a peer. I want to automatically accept it:

```swift
    func advertiser(advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: NSData?, invitationHandler: (Bool, MCSession) -> Void)
    {
        invitationHandler(true, self.session)

    }
```
    
##The iPhone "3D Mouse App"

Since the Rotating Cube App is the advertiser, my 3D Mouse App is the browser. So my monolithic view controller also implements MCNearbyServiceBrowserDelegate and, much like the advertiser, it starts browsing:

```swift
    func initialiseBrowsing()
    {
        serviceBrowser = MCNearbyServiceBrowser(peer: peerID, serviceType: serviceType)
        
        serviceBrowser.delegate = self
        serviceBrowser.startBrowsingForPeers()

    }
```

...and once it's found a peer, it sends that invitation we saw above to join the session:

```swift
    func browser(browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?)
    {
        streamTargetPeer = peerID
        
        browser.invitePeer(peerID, toSession: session, withContext: nil, timeout: 120)
        
        displayLink = CADisplayLink(target: self, selector: Selector("step"))
        displayLink?.addToRunLoop(NSRunLoop.mainRunLoop(), forMode: NSDefaultRunLoopMode)

    }
```

Here's where I also instantiate a CADisplayLink to invoke a step() method with each frame. step() does two things: it uses the streamTargetPeer I defined above to attempt to start a streaming session...

```swift
        outputStream =  try session.startStreamWithName("MotionControlStream", toPeer: streamTargetPeer)
  
        outputStream?.scheduleInRunLoop(NSRunLoop.mainRunLoop(), forMode: NSDefaultRunLoopMode)
        
        outputStream?.open()
```

...and, if that streaming session is available, sends the iPhone's attitude in 3D space (acquired using CoreMotion) over the stream:

```swift
    if let attitude = attitude where outputStream.hasSpaceAvailable
    {
        self.label.text = "stream: \(attitude.roll.radiansToDegrees()) | \(attitude.pitch.radiansToDegrees()) | \(attitude.yaw.radiansToDegrees())"
        
        outputStream.write(attitude.toBytes(), maxLength: 12)

    }
```

##Serialising and Deserialising Float Values

The attitude (of type MotionControllerAttitude) struct contains three float values for roll, pitch and yaw, but the stream only supports UInt8 bytes. To serialise and deserialise that data, I found these two functions by Rintaro on StackOverflow that take any type and convert to and from arrays of UInt8:

```swift
    func fromByteArray(value: [UInt8], _: T.Type) -> T {
        return value.withUnsafeBufferPointer {
            return UnsafePointer<T>($0.baseAddress).memory
        }
    }

    func toByteArray(var value: T) -> [UInt8] {
        return withUnsafePointer(&value) {
            Array(UnsafeBufferPointer(start: UnsafePointer<UInt8>($0), count: sizeof(T)))
        }

    }
```

My MotionControllerAttitude struct has a toBytes() method that uses toByteArray() with flatMap() to create an array of UInt8 that the outputStream.write can use:

```swift
    func toBytes() -> [UInt8]
    {
        let composite = [roll, pitch, yaw]
        
        return composite.flatMap(){toByteArray($0)}
    }
```

...and, conversely, also has an init() to instantiate an instance of itself from an array of UInt8 using fromByteArray():

```swift
    init(fromBytes: [UInt8])
    {
        roll = fromByteArray(Array(fromBytes[0...3]), Float.self)
        pitch = fromByteArray(Array(fromBytes[4...7]), Float.self)
        yaw = fromByteArray(Array(fromBytes[8...11]), Float.self)

    }
```

This is pretty brittle code - again, this is just a proof of concept!

##Rotating the Cube

Back in the Rotating Cube App, because the view controller is also acting as the NSStreamDelegate for the steam (you can see now things are yearning to be refactored!), the stream() method is invoked when the iPad receives a packet of data.

I need to check the incoming stream is actually a NSInputStream and it has bytes available. If it is and it does, I use the code above to create a MotionControllerAttitude instance from the incoming data and simply set the Euler angles on my cube:

```swift
    func stream(stream: NSStream, handleEvent eventCode: NSStreamEvent)
    {
        if let inputStream = stream as? NSInputStream where eventCode == NSStreamEvent.HasBytesAvailable
        {
            var bytes = [UInt8](count:12, repeatedValue: 0)
            inputStream.read(&bytes, maxLength: 12)

            let streamedAttitude = MotionControllerAttitude(fromBytes: bytes)
            
            dispatch_async(dispatch_get_main_queue())
            {
                self.label.text = "stream in: \(streamedAttitude.roll.radiansToDegrees()) | \(streamedAttitude.pitch.radiansToDegrees()) | \(streamedAttitude.yaw.radiansToDegrees())"
                
                self.geometryNode?.eulerAngles = SCNVector3(x: -streamedAttitude.pitch, y: streamedAttitude.yaw, z: streamedAttitude.roll)
            
            }
        }
    }
```

##In Conclusion

This project demonstrates the power of Multipeer Connectivity: whether you're creating games or content creation apps, multiple iOS devices can work together and stream any type of data quickly and reliably. Conceivably, a roomful of iPads could be all hooked up as peers and act as a render farm or a huge single multi-device display.

As always, the source code for this project is available at my GitHub repository here.

I haven't covered the CoreMotion code, this is all discussed in CoreMotion Controlled  3D sketching on an iPhone with Swift.
