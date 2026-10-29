import UIKit
import CoreMotion

class FrameView : UIImageView {
	let motionManager: CMMotionManager = CMMotionManager()
	
	override init(frame: CGRect)
	{
		super.init(frame:frame)
		self.initialize()
	}	
	
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
	
	func set(pixelBuffer: CVPixelBuffer)
	{
		let width = CVPixelBufferGetWidth(pixelBuffer)
		let height = CVPixelBufferGetHeight(pixelBuffer)
	    var img = CIImage(cvPixelBuffer: pixelBuffer)
	    if (width > height) {
			img = img.oriented(self.rotateOrientation)
	    }
		super.image = UIImage(ciImage: img)
	}
	
	var rotateOrientation: CGImagePropertyOrientation {
		
		guard let accelerometerData = motionManager.accelerometerData else {
			return .up
		}
	
	    let x = accelerometerData.acceleration.x;
	
	    if (x < 0) {
			return .right;
	    }
		return .left;
	}
	
	func initialize()
	{
		self.contentMode = .scaleAspectFit;
	
		if (motionManager.isAccelerometerAvailable) {
			motionManager.accelerometerUpdateInterval = 0.1
			motionManager.startAccelerometerUpdates()
		}
	}
}
