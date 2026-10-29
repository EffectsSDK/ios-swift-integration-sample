
import AVFoundation
import CoreMotion

protocol CapturePipelineDelegate: AnyObject
{
	func captureVideoFrame(_ frame:CVPixelBuffer);
	func recordingFinished(outputURL:URL);
}

class SimpleCameraCapturer: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate
{
	let queue: DispatchQueue
	var session: AVCaptureSession? = nil
	var videoOutput: AVCaptureVideoDataOutput? = nil
	var videoInput: AVCaptureDeviceInput? = nil
	var videoConnection: AVCaptureConnection? = nil
	let frameCallback: (CMSampleBuffer)->Void
	
	let operationQueue: OperationQueue
	let motionManager = CMMotionManager()
	var currentOrientation: AVCaptureVideoOrientation = .portrait
	
	init(queue: DispatchQueue?, callback:@escaping (CMSampleBuffer)->Void)
	{
		self.queue = queue ?? DispatchQueue(label:"com.tsvb.simple-camera-capturer")
		self.frameCallback = callback
		self.operationQueue = OperationQueue()
		self.operationQueue.underlyingQueue = self.queue
	}
	
	func start()
	{
		self.queue.async {
			if (nil == self.session) {
				do {
					let ok = try self.setupCamera()
					if (!ok) {
						return;
					}
				}
				catch _ {
					return
				}
	        }
	
			guard let session = self.session else {
				return
			}
	        if (!session.isRunning) {
				session.startRunning()
	        }
	    }
	
	    if(!motionManager.isAccelerometerAvailable) {
	        return;
	    }
	
	    motionManager.accelerometerUpdateInterval = 0.1;
		motionManager.startAccelerometerUpdates(to:self.operationQueue){
			(accelerometerDataOpt: CMAccelerometerData?, error: Error?) in
			guard let accelerometerData = accelerometerDataOpt else {
				return
			}
	
	        let x = accelerometerData.acceleration.x;
	        let y = accelerometerData.acceleration.y;
	
			var orientation = self.currentOrientation
	        if (x >= 0.75) {
				orientation = .landscapeLeft;
	        }
	        else if(x <= -0.75) {
				orientation = .landscapeRight;
	        }
	        else if (y <= -0.75) {
				orientation = .portrait;
	        }
	        else if (y >= 0.75) {
				orientation = .portraitUpsideDown;
	        }
	
			if (orientation != self.currentOrientation) {
				self.currentOrientation = orientation;
				self.session?.beginConfiguration()
				self.videoConnection?.videoOrientation = orientation
				self.session?.commitConfiguration()
	        }
	    }
	}
	
	func stop()
	{
		self.queue.async {
			guard let session = self.session else {
				return
			}
			if (session.isRunning) {
				session.stopRunning()
			}
		}
	
		motionManager.stopAccelerometerUpdates()
	}
	
	func setupCamera() throws -> Bool
	{
		let session = AVCaptureSession()
		session.beginConfiguration()
		session.sessionPreset = .hd1280x720
		
		guard let device = AVCaptureDevice.default(
			.builtInWideAngleCamera,
			for: .video,
			position:.front
		) ?? AVCaptureDevice.default(for: .video) else {
			return false
		}
		
		let input = try AVCaptureDeviceInput(device: device)
		
		guard session.canAddInput(input) else {
			return false;
		}
		
		session.addInput(input);
		
		let videoSettings: [String : Any] = [
			kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
		];
		
		let output = AVCaptureVideoDataOutput()
		output.videoSettings = videoSettings;
		output.alwaysDiscardsLateVideoFrames = true;
		output.setSampleBufferDelegate(self, queue:self.queue)
		
		guard session.canAddOutput(output) else {
			return false
		}
		session.addOutput(output)
		
		self.videoConnection = output.connection(with: .video)
		self.videoConnection?.videoOrientation = self.currentOrientation;
		self.videoConnection?.isVideoMirrored = true;
		
		session.commitConfiguration();
		self.session = session;
		self.videoInput = input;
		self.videoOutput = output;
		return true;
	}
	
	func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection)
	{
		self.frameCallback(sampleBuffer);
	}
}
