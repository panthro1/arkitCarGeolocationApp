//
//  ViewController.swift
//  ARKitCarGeolocationApp
//
//  Created by Martin on 10/2/18.
//  Copyright © 2018 Martin. All rights reserved.
//

import UIKit
import ARKit
import SceneKit
import CoreLocation
import PusherSwift

class ViewController: UIViewController, ARSCNViewDelegate, CLLocationManagerDelegate {

    @IBOutlet weak var sceneView: ARSCNView!
    @IBOutlet weak var statusTextView: UITextView!
    
    let locationManager = CLLocationManager()
    var userLocation = CLLocation()
    var modelNode: SCNNode!
    let rootNodeName = "Car"
    var originalTransform: SCNMatrix4!
    var heading: Double! = 0.0
    
    var distance: Float! = 0.0 {
      
        didSet {
        setStatusText()
        }
    }
    
    var status: String! {
        
        didSet {
            setStatusText()
        }
    }
    
    let pusher = Pusher(
        key:"9534396ca6dfb8b40428",
        options: PusherClientOptions(
            authMethod: .inline(secret: "6a5f535d93487250f10b"),
            host: .cluster("eu")
      )
    )
    
    var channel: PusherChannel!
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        //Set the view's delegate
        sceneView.delegate = self
        
        //Create a new scene
        let scene = SCNScene()
        
        //Set the scene to the view
        sceneView.scene = scene
        
        //Start location services
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
        
        //Set the initial status
        status = "Getting user location..."
        
        //Set a padding in the text view
        statusTextView.textContainerInset = UIEdgeInsets.init(top: 20.0, left: 10.0, bottom: 10.0, right: 0.0)
        
        
        
    }
    
    func setStatusText(){
        
        var text = "Status: \(status!)\n"
        text += "Distance: \(String(format: "%.2f m", distance))"
        statusTextView.text = text
        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        //Create a session configuration
        let configuration = ARWorldTrackingConfiguration()
        
        //The option gravityAndHeading will set the y-axis to the direction of gravity as detected by the device, and the x and z-axes to the longitude and latitude
        //directions as measured by Location Services.
        configuration.worldAlignment = .gravityAndHeading
        
        //Run the view's session
        sceneView.session.run(configuration)
        
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        //Pause the view's session
        sceneView.session.pause()
    }
    
    //Mark: - CLLocationManager
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
         //Implementing this method is required
        print(error.localizedDescription)
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        
        if status == .authorizedWhenInUse {
           locationManager.requestLocation()
        }
    }

    //Once the user's location is received, take the last element of the array, update the status, and connect to Pusher
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        
        if let location = locations.last {
            userLocation = location
            status = "Connecting to Pusher..."
            
            self.connectToPusher()
            
            
            
        }
    }
    
    //Mark: - Utility methods
    
    func connectToPusher(){
        
        //subscribe to channel and bind to event
        
        let channel = pusher.subscribe("private-channel")
        
        let _ = channel.bind(eventName: "client-new-location", callback: { (data: Any?) -> Void in
            
            if let data = data as? [String : AnyObject] {
                
                print("getting the data from the pusher")
                
                if let latitude  = Double(data["latitude"] as! String),
                   let longitude = Double(data["longitude"] as! String),
                    let heading   = Double(data["heading"] as! String) {
                    
                    self.status  = "Driver's location received"
                    self.heading = heading
                    self.updateLocation(latitude, longitude)
                    
                    print("it's all ok")
                    
                }
                
                
            }
        })
        
        pusher.connect()
        status = "Waiting to receive location events..."
        
        print("connected to pusher")
    }
    
    func updateLocation(_ latitude: Double, _ longitude: Double){
        
        print("update location called")
        
        let location = CLLocation(latitude: latitude, longitude: longitude)
        self.distance = Float(location.distance(from: userLocation))
        
        if self.modelNode == nil {
             let modelScene = SCNScene(named: "art.scnassets/Car.dae")!
             self.modelNode = modelScene.rootNode.childNode(withName: rootNodeName, recursively: true)!
        
        //You need to move the pivot of the model to its center in the y-axis, so it can be rotated without changing its position
        
            let (minBox, maxBox) = self.modelNode.boundingBox
            self.modelNode.pivot = SCNMatrix4MakeTranslation(0, (maxBox.y - minBox.y)/2, 0)
            
        // Save original transform to calculate future rotations
            self.originalTransform = self.modelNode.transform
            
        // Position the model in the correct place
            positionModel(location)
            
        // Add the model to the scene
            sceneView.scene.rootNode.addChildNode(self.modelNode)
            
        // Create arrow from the emoji
            let arrow = makeBillboardNode("⬇️".image()!)
        // Postion it on top of the car
            arrow.position = SCNVector3Make(0, 4, 0)
        // Add it as a child of the car model
            self.modelNode.addChildNode(arrow)
            
            print("updating location.....")
            
        }
        else {
            // Begin animation
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 1.0
            
            // Position the model in the correct place
            positionModel(location)
            
            // End animation
            SCNTransaction.commit()
        }
    }
    
    func positionModel(_ location: CLLocation) {
        
        // Rotate node
        self.modelNode.transform = rotateNode(Float(-1 * (self.heading - 180).toRadians()), self.originalTransform)
        
        // Translate node
        self.modelNode.position = translateNode(location)
        
        //Scale node
        self.modelNode.scale = scaleNode(location)
        
        print("postioning the model")
    }
    
    // In ARKit, rotation in the y-axis is counterclockwise (and handled in radians), so we need to substract 180 degrees and make the angle negative.
    // This is the definition od the method rotateNode:
    
    func rotateNode(_ angleInRadians: Float, _ transform: SCNMatrix4) -> SCNMatrix4 {
        
        let rotation = SCNMatrix4MakeRotation(angleInRadians, 0, 1, 0)
        return SCNMatrix4Mult(transform, rotation)
    }
    
    // Scale the node in proportion to the distance. They are inversely proportional - the greater the distance, the less the scale.
    // In my case, i just divide 1000 by the distance and don't allow the value to be less than 1.5 or great than 3:
    
    func scaleNode(_ location: CLLocation) -> SCNVector3 {
        
        let scale = min( max(Float(1000 / distance), 1.5), 3)
        return SCNVector3(x: scale, y: scale, z: scale)
    }
    
    // To translate the node, you have to calculate the transformation matrix and get the position values that matrix (from its fourth column, referenced by a zero-based index):
    
    func translateNode(_ location: CLLocation) -> SCNVector3 {
        
        let locationTransform = transformMatrix(matrix_identity_float4x4, userLocation, location)
        return positionFromTransform(locationTransform)
    }
    
    func positionFromTransform(_ transform: simd_float4x4) -> SCNVector3{
        
        return SCNVector3Make(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
    }
    
    func transformMatrix(_ matrix: simd_float4x4, _ originLocation: CLLocation, _ driverLocation: CLLocation) -> simd_float4x4 {
        
        let bearing = bearingBetweenLocations(userLocation, driverLocation)
        let rotationMatrix = rotateAroundY(matrix_identity_float4x4, Float(bearing))
        let position = vector_float4(0.0, 0.0, -distance, 0.0)
        
        let translationMatrix = getTranslationMatrix(matrix_identity_float4x4, position)
        
        let transformMatrix = simd_mul(rotationMatrix, translationMatrix)
        
        return simd_mul(matrix, transformMatrix)
        
    }
    
    func getTranslationMatrix(_ matrix: simd_float4x4, _ translation: vector_float4) -> simd_float4x4 {
        
        var matrix = matrix
        matrix.columns.3 = translation
        return matrix
    }
    
    func rotateAroundY(_ matrix: simd_float4x4, _ degrees: Float) -> simd_float4x4 {
        
        var matrix = matrix
        
        matrix.columns.0.x = cos(degrees)
        matrix.columns.0.z = -sin(degrees)
        
        matrix.columns.2.x = sin(degrees)
        matrix.columns.2.z = cos(degrees)
        
        return matrix.inverse
        
    }
    
    
    func bearingBetweenLocations(_ originLocation: CLLocation, _ driverLocation: CLLocation) -> Double {
        
        let lat1 = originLocation.coordinate.latitude.toRadians()
        let lon1 = originLocation.coordinate.longitude.toRadians()
        
        let lat2 = driverLocation.coordinate.latitude.toRadians()
        let lon2 = driverLocation.coordinate.longitude.toRadians()
        
        let longitudeDiff = lon2 - lon1
        
        let y = sin(longitudeDiff) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(longitudeDiff)
        
        return atan2(y, x)
    }
    
    func makeBillboardNode(_ image: UIImage) -> SCNNode {
        
        let plane = SCNPlane(width: 10, height: 10)
        plane.firstMaterial?.diffuse.contents = image
        let node = SCNNode(geometry: plane)
        node.constraints = [SCNBillboardConstraint()]
        return node
        
    }
    


}

