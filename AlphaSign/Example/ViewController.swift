import UIKit
import CoreML
import AVFoundation

class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate, TrackerDelegate {
  
  // MARK: - ImageView / Image related properties
  private var imageSize: CGSize?
  private static let POINT_SIZE: CGFloat = 2
  
//    @IBOutlet weak var imageView: UIImageView!
    var imageView = UIImageView(frame: .zero)
    @IBOutlet weak var toggleView: UISwitch!
//    var previewLayer: AVCaptureVideoPreviewLayer!
    var previewLayer: AVCaptureVideoPreviewLayer?
    var pointsLayer = CAShapeLayer()
    @IBOutlet weak var xyLabel:UILabel!
    @IBOutlet weak var featurePoint: UIView!
    let camera = Camera()
    let tracker: HandTracker = HandTracker()!
    var w = CGFloat()
    var h = CGFloat()
    var label = UILabel()
    var convertedPoints = [CGPoint]()
  var rounding: Float = 100
  var minProb: Float = 0.97
  var tapped = UITapGestureRecognizer()
  var pressed = UILongPressGestureRecognizer()
  var safe_w = CGFloat()
  var safe_h = CGFloat()
  
  var model: Model?
  var buffer = [[Float32]]()
  
  private func createEmptyFrame() -> [Float32] {
    return [Float32](repeating: 0, count: 21 * 3)
  }
  
  private func createEmptyDoubleFrame() -> [Float32] {
    return [Float32](repeating: 0, count: 21 * 3 * 2)
  }
    
    
    override func viewDidLoad() {
      super.viewDidLoad()
      self.w = CGFloat(self.view.frame.width)
      self.h = CGFloat(self.view.frame.height)
      self.safe_w = CGFloat(self.view.safeAreaLayoutGuide.layoutFrame.width)
      self.safe_h = CGFloat(self.view.safeAreaLayoutGuide.layoutFrame.height)
//      print("here1")
      
        setupVideoPreview()
        setupLabel()
//        setupTap()
        setupPress()
        camera.setSampleBufferDelegate(self)
        camera.start()
        
        tracker.startGraph()
        tracker.delegate = self
        
        self.model = try? Model()
//        print(self.model)
        
    }
    
  func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
      let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
      tracker.processVideoFrame(pixelBuffer)

      DispatchQueue.main.async {
        // Need to capture the size of the image to draw the debug points
        guard let buffer = pixelBuffer else { return }
        let image = UIImage(ciImage: CIImage(cvPixelBuffer: buffer))
        self.imageSize = image.size
      }
  }
  
  private func setupTap()
  {
    tapped = UITapGestureRecognizer(target: self, action: #selector(doubleTapped))
    tapped.numberOfTapsRequired = 2
    view.addGestureRecognizer(tapped)
  }
  @objc func doubleTapped() {
    let alphapoints = pointsLayer.opacity
    pointsLayer.opacity = 1 - alphapoints
    print("[alpha] -- \(alphapoints)")
  }
  
  private func setupPress()
  {
    pressed = UILongPressGestureRecognizer(target: self, action: #selector(longPressed))
    pressed.minimumPressDuration = 0
    view.addGestureRecognizer(pressed)
  }
  @objc func longPressed(gestureReconizer: UILongPressGestureRecognizer) {
    guard let previewLayer = self.previewLayer else { return }
    let location = gestureReconizer.location(in: view)
//    print("[location] -- \(location)")
    if (location.x > (self.w*0.85)) {
      previewLayer.opacity = 1
      pointsLayer.opacity = 1 - previewLayer.opacity
    }
    else if (location.x < (self.w*0.15)) {
      previewLayer.opacity = 0
      pointsLayer.opacity = 1 - previewLayer.opacity
    }
    else {
      previewLayer.opacity = Float((location.x / 350))
      pointsLayer.opacity = min(1, (1.2 - previewLayer.opacity))
    }
    
  }
  
  private func setupVideoPreview() {
    previewLayer = AVCaptureVideoPreviewLayer(session: camera.session)
    guard let previewLayer = self.previewLayer else { return }
    self.view.layer.addSublayer(previewLayer)
    previewLayer.frame = view.frame
    previewLayer.videoGravity = AVLayerVideoGravity.resizeAspectFill
    self.view.layer.addSublayer(pointsLayer)
    pointsLayer.frame = view.frame
    pointsLayer.strokeColor = UIColor.cyan.cgColor
    pointsLayer.lineCap = .round
    pointsLayer.opacity = 0
  }
  
  private func setupLabel()
  {
    let height = (h/6)
    let xval = (view.frame.maxX * (1/8))
    let yval = (view.frame.maxY - (height) - (view.frame.height/10))
    let labelRect = CGRect(x: xval , y: yval, width:(view.frame.width * (3 / 4)), height: height)
    label.frame = labelRect
    label.backgroundColor = UIColor.white.withAlphaComponent(0.6)
    label.textColor = UIColor.black
    label.layer.masksToBounds = true
    label.layer.cornerRadius = 25
    label.text = ""
    label.font = label.font.withSize(25)
    label.textAlignment = .center
    view.addSubview(label)
  }
  
  func transformData( _ landmarks: [Landmark] ) -> [Float32]? {
    
//    let imageWidth = self.w
    let imageWidth = 1080

    let left = landmarks
      .compactMap { $0.x }
      .min() ?? 0
    let right = landmarks
      .compactMap { $0.x }
      .max() ?? 0
    
    let top = landmarks
      .compactMap { $0.y }
      .min() ?? 0
    
    guard left > 0.001, right > 0.001, top > 0.001 else { return nil }
    let widthInImage = Float(imageWidth) * (right - left)
    guard widthInImage > 0 else { return nil }
    let scaleFactor = 400 / widthInImage
    let translatedLandmarks = landmarks
      .compactMap { lm -> [Float] in
        return [
          // todo: what do do about mirroring?
          round(self.rounding * scaleFactor * (lm.x - left)) / self.rounding,
          round(self.rounding * scaleFactor * (lm.y - top)) / self.rounding,
          round(self.rounding * scaleFactor * lm.z) / self.rounding
        ]
      }
      .reduce([], +)
    
    return translatedLandmarks + self.createEmptyFrame()
  
  }
  
    func handTracker(_ handTracker: HandTracker!, didOutputLandmarks landmarks: [Landmark]!, andHand handSize: CGSize) {
      
      DispatchQueue.main.async { [weak self] in
        self?.updateVisiblePoints(landmarks: landmarks)
      }
      
      guard let frame = transformData(landmarks) else {return}
//      transformTest(frame)
//      print("[frame] -- \(frame)")
//      print("[frame] -- \(ret_arr)")
      
      self.buffer.append(frame)
      
//      print("size of buffer -- \(self.buffer.count)")
      
      if self.buffer.count == 10 {
        if let bufferInput = try? MLMultiArray(shape: [1, 10, 126], dataType: .float32) {
          for (fidx, frame) in self.buffer.enumerated() {
            for (vidx, frameValue) in frame.enumerated() {
              bufferInput[[0,fidx, vidx] as [NSNumber]] = frameValue as NSNumber
            }
          }
          
          if let output = try? self.model?.prediction(lstm_input: bufferInput) {
            let prob = Float(output.Identity[output.classLabel] ?? 0)
            print("[idict] \(prob)")
            if prob > minProb {
              DispatchQueue.main.async {
                self.label.text = output.classLabel
                
              }
            }
//            print("[output] -- \(output.classLabel)")
            
           
          }
        }
      }
      
      if self.buffer.count == 10 {
        self.buffer.removeFirst()
        print(self.buffer.count)
      }
      
     
       
    }
  
  private func updateVisiblePoints(landmarks: [Landmark]) {
    // Assume this runs on the foreground thread
    
    guard let imageSize = self.imageSize else { return }
    let viewSize = self.view.frame.size
    
    guard imageSize.width > 0, imageSize.height > 0,
          viewSize.width > 0, viewSize.height > 0 else { return }
    
    // The preview is configured for .aspectFill which means that the video frame will scale
    // PRESERVING ITS ASPECT RATIO until the screen is complete filled.
    
    // Which is the limiting factor
    
    let scaleFactor: CGFloat = {
      // Assume the widths are the same..
      let scaleFactorIfWidthAreTheSame = viewSize.width / imageSize.width
      let imageHeightAfterScale = imageSize.height * scaleFactorIfWidthAreTheSame
      
      if imageHeightAfterScale >= viewSize.height {
        return scaleFactorIfWidthAreTheSame
      }
      
      // Assumme the heights are the same..
      let scaleFactorIfHeightAreTheSame = viewSize.height / imageSize.height
      let imageWidthAfterScale = imageSize.width * scaleFactorIfHeightAreTheSame
      
      if imageWidthAfterScale >= viewSize.width {
        return scaleFactorIfHeightAreTheSame
      }
      
      // I dont know why this would ever happen
      return -1
    }()
    
    guard scaleFactor > 0 else { return }
    
    let imageWidthInView = imageSize.width * scaleFactor
    let imageHeightInView = imageSize.height * scaleFactor
    let xOffset = (viewSize.width - imageWidthInView) / 2
    let yOffset = (viewSize.height - imageHeightInView) / 2
    
    let combinedPath = CGMutablePath()
    landmarks
      .compactMap { lm -> CGRect in
        // Here we use the scale factor and the offsets to place the landmarks in the view's
        // coordinate system
        let lmX = CGFloat(lm.x) * imageSize.width * scaleFactor + xOffset
        let lmY = CGFloat(lm.y) * imageSize.height * scaleFactor + yOffset
        return CGRect(x: lmX, y: lmY, width: Self.POINT_SIZE, height: Self.POINT_SIZE)
      }
      .forEach { rect in
        let dotPath = UIBezierPath(ovalIn: rect)
        combinedPath.addPath(dotPath.cgPath)
      }
    
    self.pointsLayer.path = combinedPath
    self.pointsLayer.didChangeValue(for: \.path)
    
    
    /*
     for lm in landmarks
     {
//        let point = CGPoint(x: CGFloat(CGFloat(lm.x) * self.w), y: CGFloat(CGFloat(lm.y) * self.h))
       let point = CGPoint(x: CGFloat(CGFloat(lm.x) * self.safe_w), y: CGFloat(CGFloat(lm.y) * self.safe_h))
       convertedPoints.append(point)
     }
     
     let combinedPath = CGMutablePath()

     for point in convertedPoints {
         let dotPath = UIBezierPath(ovalIn: CGRect(x: point.x, y: point.y, width: 2, height: 2))
         combinedPath.addPath(dotPath.cgPath)
     }

     self.pointsLayer.path = combinedPath
     DispatchQueue.main.async {
         self.pointsLayer.didChangeValue(for: \.path)
     }
     convertedPoints.removeAll()
     */
    
  }
    
    func handTracker(_ handTracker: HandTracker!, didOutputPixelBuffer pixelBuffer: CVPixelBuffer!) {
//        DispatchQueue.main.async {
////            if self.toggleView.isOn {
//                self.imageView.image = UIImage(ciImage: CIImage(cvPixelBuffer: pixelBuffer))
//            }
////        }
    }
}

extension Collection {
    /// Returns the element at the specified index if it is within bounds, otherwise nil.
    subscript (safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

extension CGFloat {
    func ceiling(toDecimal decimal: Int) -> CGFloat {
        let numberOfDigits = CGFloat(abs(pow(10.0, Double(decimal))))
        if self.sign == .minus {
            return CGFloat(Int(self * numberOfDigits)) / numberOfDigits
        } else {
            return CGFloat(ceil(self * numberOfDigits)) / numberOfDigits
        }
    }
}

extension Double {
    func ceiling(toDecimal decimal: Int) -> Double {
        let numberOfDigits = abs(pow(10.0, Double(decimal)))
        if self.sign == .minus {
            return Double(Int(self * numberOfDigits)) / numberOfDigits
        } else {
            return Double(ceil(self * numberOfDigits)) / numberOfDigits
        }
    }
}
