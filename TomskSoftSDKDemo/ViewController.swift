
import UIKit
import AVFoundation

import TSVB

func synchronized<ReturnT>(_ obj: AnyObject, closure:()->ReturnT) -> ReturnT
{
	objc_sync_enter(obj)
	defer { objc_sync_exit(obj) }
	return closure()
}

class ViewController: UIViewController {
	let pipelineQueue = DispatchQueue(label: "com.tsvb.camera-pipeline");
	let pipelineControlQueue = DispatchQueue(label: "com.tsvb.pipeline-control")
	let frameView = FrameView(frame: CGRect(x: 0, y: 0, width: 0, height: 0))
	lazy var fpsLabel = makeInfoLabel()
	lazy var timeLabel = makeInfoLabel()
	var timer: Timer? = nil

	var blurEnabled = false
	var replaceEnabled = false
	var denoiseEnabled = false
	var beautificationEnabled = false
	var colorCorrectionEnabled = false
	var smartZoomEnabled = false
	var lowLightEnabled = false;
	var sharpeningEnabled = false;

	var capturer: SimpleCameraCapturer?
	var sdkFactory = TSVB.SDKFactory()
	var frameFactory: FrameFactory?
	var pipeline: Pipeline?
	let metrics = Metrics()

	lazy var blurButton  = makeFeatureButton(
		title: "Blur",
		onTouchHandler: #selector(toggleBlurBackground)
	)
	lazy var replacementButton = makeFeatureButton(
		title: "Replacement",
		onTouchHandler: #selector(toggleReplaceBackground)
	)
	lazy var denoiseButton = makeFeatureButton(
		title: "Denoise",
		onTouchHandler: #selector(toggleDenoiseBackground)
	)
	lazy var beautificationButton = makeFeatureButton(
		title: "Beautification",
		onTouchHandler: #selector(toggleBeautification)
	)
	lazy var colorCorrectionButton = makeFeatureButton(
		title: "ColorCorrection",
		onTouchHandler: #selector(toggleColorCorrection)
	)
	lazy var smartZoomButton = makeFeatureButton(
		title: "Auto Zoom",
		onTouchHandler: #selector(toggleSmartZoom)
	)
	lazy var lowLightButton = makeFeatureButton(
		title: "Adjust for Low Light",
		onTouchHandler: #selector(toggleLowLight)
	)
	lazy var sharpeningButton = makeFeatureButton(
		title: "Sharpening",
		onTouchHandler: #selector(toggleSharpening)
	)
	
	override func viewDidLoad() {
		super.viewDidLoad()
		
		Task {
			do {
				let result = try await sdkFactory.auth(customerID: "CUSTOMER_ID")
				if (result.status == .active) {
					startDemo()
				}
				else {
					handleAuthorizationFailure(result: result);
				}
			}
			catch let e {
				handleAuthorizationFailure(error: e)
			}
		}
	}
	
	func startDemo() {
		let rootView = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: 0));
		rootView.addSubview(frameView);
		frameView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
		
		rootView.addSubview(makeButtonPanel())
		
		rootView.addSubview(timeLabel)
		rootView.addSubview(fpsLabel)
		
		self.view = rootView
		
		pipeline = sdkFactory.newPipeline()
		frameFactory = sdkFactory.newFrameFactory()
		
		Task {
			await enableReplaceBackground()
			setFeatureEnabledButtonState(replacementButton, enabled: replaceEnabled)
		}
		
		capturer = SimpleCameraCapturer(
			queue: pipelineQueue,
			callback: {buffer in self.processFrame(buffer: buffer)}
		)
		capturer?.start()
		
		timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) {_ in
			self.updateTimeAndFPSLabels()
		}
	}

	func processFrame(buffer: CMSampleBuffer) {
		guard let inputFrame = CMSampleBufferGetImageBuffer(buffer) else { return }
		
		let startTime = Date()
		let result = synchronized(pipeline!) {
			return pipeline?.process(pixelBuffer: inputFrame, error:nil)
		}
		let endTime = Date()
		let neededAddToMierics = (nil != result)
		let outputFrame = result?.toCVPixelBuffer() ?? inputFrame
		
		DispatchQueue.main.async {
			if neededAddToMierics {
				let interval = DateInterval(start: startTime, end: endTime)
				self.metrics.didProcessFrame(for: interval)
				self.metrics.didCameraFrame(endTime)
			}
			self.frameView.set(pixelBuffer: outputFrame)
		}
	}

	@objc func toggleBlurBackground()
	{
		Task {
			guard let pipeline = self.pipeline else { return }
			blurButton.isEnabled = false
			let neededEnableBlur = !blurEnabled
			blurEnabled = await inControlQueue {
				return synchronized(pipeline) {
					if neededEnableBlur {
						let ok = pipeline.enableBlurBackground(power: 0.3) == .ok
						if ok {
							pipeline.disableReplaceBackground()
							pipeline.disableDenoiseBackground()
						}
						return ok
					}
					
					pipeline.disableBlurBackground()
					return false
				}
			}
			if blurEnabled {
				replaceEnabled = false
				denoiseEnabled = false
			}
			
			blurButton.isEnabled = true
			updateBackgroundFeatureButtons()
		}
	}

	func enableReplaceBackground() async {
		guard let pipeline = self.pipeline else { return }
		replacementButton.isEnabled = false
		defer { replacementButton.isEnabled = true }
		
		let background = await loadBackgroundFrame()
		replaceEnabled = await inControlQueue {
			return synchronized(pipeline) {
				var controller = nil as ReplacementController?
				let error = pipeline.enableReplaceBackground(&controller)
				let ok = error == .ok
				if ok {
					controller?.background = background
					pipeline.disableBlurBackground()
					pipeline.disableDenoiseBackground()
				}
				return ok
			}
		}
		
		if replaceEnabled {
			blurEnabled = false
			denoiseEnabled = false
		}
		updateBackgroundFeatureButtons()
	}

	@objc func toggleReplaceBackground()
	{
		Task {
			if replaceEnabled {
				guard let pipeline = self.pipeline else { return }
				replacementButton.isEnabled = false
				await inControlQueue {
					synchronized(pipeline){                     pipeline.disableReplaceBackground()
					}
				}
				replaceEnabled = false
				replacementButton.isEnabled = true
				updateBackgroundFeatureButtons()
			}
			else {
				await enableReplaceBackground()
			}
		}
	}

	@objc func toggleDenoiseBackground()
	{
		Task {
			guard let pipeline = self.pipeline else { return }
			denoiseButton.isEnabled = false
			let neededEnableDenoise = !denoiseEnabled
			denoiseEnabled = await inControlQueue {
				return synchronized(pipeline) {
					if neededEnableDenoise {
						let ok = pipeline.enableDenoiseBackground() == .ok
						if ok {
							pipeline.disableReplaceBackground()
							pipeline.disableBlurBackground()
						}
						return ok
					}
					
					pipeline.disableDenoiseBackground()
					return false
				}
			}
			if denoiseEnabled {
				replaceEnabled = false
				blurEnabled = false
			}
			
			denoiseButton.isEnabled = true
			updateBackgroundFeatureButtons()
		}
	}

	@objc func toggleBeautification()
	{
		Task {
			guard let pipeline = self.pipeline else { return }
			beautificationButton.isEnabled = false
			let neededEnableBeautification = !beautificationEnabled
			beautificationEnabled = await inControlQueue {
				return synchronized(pipeline) {
					if neededEnableBeautification {
						let error = pipeline.enableBeautification()
						return error == .ok
					}
					
					pipeline.disableBeautification()
					return false
				}
			}
			
			beautificationButton.isEnabled = true
			setFeatureEnabledButtonState(
				beautificationButton,
				enabled:beautificationEnabled
			)
		}
	}

	@objc func toggleColorCorrection()
	{
		Task {
			guard let pipeline = self.pipeline else { return }
			colorCorrectionButton.isEnabled = false
			let neededEnableColorCorrection = !colorCorrectionEnabled
			colorCorrectionEnabled = await inControlQueue {
				return synchronized(pipeline) {
					if neededEnableColorCorrection {
						let error = pipeline.enableColorCorrection()
						return error == .ok
					}
					
					pipeline.disableColorCorrection()
					return false
				}
			}
			colorCorrectionButton.isEnabled = true
			setFeatureEnabledButtonState(
				colorCorrectionButton,
				enabled:colorCorrectionEnabled
			)
		}
	}

	@objc func toggleSmartZoom()
	{
		Task {
			guard let pipeline = self.pipeline else { return }
			smartZoomButton.isEnabled = false
			let neededEnableSmartZoom = !smartZoomEnabled
			smartZoomEnabled = await inControlQueue {
				return synchronized(pipeline) {
					if neededEnableSmartZoom {
						let error = pipeline.enableSmartZoom()
						return error == .ok
					}
					
					pipeline.disableSmartZoom()
					return false
				}
			}
			smartZoomButton.isEnabled = true
			setFeatureEnabledButtonState(
				smartZoomButton,
				enabled:smartZoomEnabled
			)
		}
	}

	@objc func toggleLowLight()
	{
		Task {
			guard let pipeline = self.pipeline else { return }
			lowLightButton.isEnabled = false
			let neededEnableLowLight = !lowLightEnabled
			lowLightEnabled = await inControlQueue {
				return synchronized(pipeline) {
					if neededEnableLowLight {
						let error = pipeline.enableLowLightAdjustment()
						return error == .ok
					}
					
					pipeline.disableLowLightAdjustment()
					return false
				}
			}
			lowLightButton.isEnabled = true
			setFeatureEnabledButtonState(
				lowLightButton,
				enabled:lowLightEnabled
			)
		}
	}

	@objc func toggleSharpening()
	{
		Task {
			guard let pipeline = self.pipeline else { return }
			sharpeningButton.isEnabled = false
			let neededEnableSharpening = !sharpeningEnabled
			sharpeningEnabled = await inControlQueue {
				return synchronized(pipeline) {
					if neededEnableSharpening {
						let error = pipeline.enableSharpening()
						return error == .ok
					}
					
					pipeline.disableSharpening()
					return false
				}
			}
			sharpeningButton.isEnabled = true
			setFeatureEnabledButtonState(
				sharpeningButton,
				enabled:sharpeningEnabled
			)
		}
	}

	func updateBackgroundFeatureButtons()
	{
		setFeatureEnabledButtonState(blurButton, enabled:blurEnabled)
		setFeatureEnabledButtonState(replacementButton, enabled:replaceEnabled)
		setFeatureEnabledButtonState(denoiseButton, enabled:denoiseEnabled)
	}

	func loadBackgroundFrame() async -> Frame?
	{
		let factory = frameFactory
		return await Task.detached{
			let backgroundFilePath =
				Bundle.main.path(forResource: "background_image", ofType: "jpg")
			let backgroundFrame = factory?.image(withContentOfFile: backgroundFilePath)
			return backgroundFrame
		}.value
	}

	func inControlQueue<ReturnT>(closure:@escaping ()->ReturnT ) async -> ReturnT
	{
		return await withCheckedContinuation{ continuation in
			pipelineControlQueue.async {
				let result = closure()
				continuation.resume(returning: result)
			}
		}
	}

	func makeButtonPanel() -> UIScrollView
	{
		let buttons = [
			blurButton,
			replacementButton,
			denoiseButton,
			beautificationButton,
			colorCorrectionButton,
			smartZoomButton,
			lowLightButton,
			sharpeningButton
		]
		
		var width: CGFloat = 0;
		var height: CGFloat = 0;
		for button in buttons {
			let size = button.intrinsicContentSize
			width += size.width
			height = max(size.height, height);
		}
		
		let buttonStack = UIStackView(arrangedSubviews: buttons)
		buttonStack.alignment = .center;
		buttonStack.isLayoutMarginsRelativeArrangement = true;
		
		let stackFrame = CGRect(x: 0, y: 0, width: width, height: height);
		buttonStack.frame = stackFrame
		
		let scroll = UIScrollView(frame: CGRect.zero)
		scroll.addSubview(buttonStack)
		scroll.contentInset = UIEdgeInsets(top: 0, left: 48, bottom: 0, right: 48)
		scroll.contentSize = buttonStack.frame.size
		scroll.contentOffset = CGPoint(x: -48, y: 0)
		scroll.frame = CGRect(x: 0, y: -height, width: 0, height: height)
		scroll.autoresizingMask = [.flexibleTopMargin, .flexibleWidth]
		scroll.backgroundColor = UIColor(red:0, green:0, blue:0, alpha:0.2);
		
		return scroll;
	}

	func makeFeatureButton(title: String, onTouchHandler:Selector) -> UIButton
	{
		let button = UIButton(type: .system)
		button.setTitle(title, for: .normal)
		button.titleLabel?.font = UIFont.boldSystemFont(ofSize: 24)
		button.setTitleColor(standardButtonColor, for: .normal)
		button.setTitleColor(UIColor.gray, for:.disabled)
		button.addTarget(self, action:onTouchHandler, for: .touchDown)
		button.contentEdgeInsets = UIEdgeInsets(
			top: 20, left: 8, bottom: 20, right: 8
		)
		
		return button
	}

	func makeInfoLabel() -> UILabel
	{
		let label = UILabel(frame: CGRect.zero)
		label.textColor = UIColor.white
		label.textAlignment = .center;
		label.backgroundColor = UIColor(red:0, green:0, blue:0, alpha:0.3)
		label.autoresizingMask = .flexibleLeftMargin;
		return label;
	}

	func updateTimeAndFPSLabels()
	{
		let fpsText = String(format: "%1.1f fps", metrics.cameraFPS)
		fpsLabel.text = fpsText
		let timeText = String(
			format: "%1.2fms per frame",
			metrics.averageTimePerFrame * 1000
		)
		timeLabel.text = timeText
		
		updateLabelPos(fpsLabel, topPos:38)
		let fpsLabelBottomPos =
			fpsLabel.frame.origin.y + fpsLabel.frame.size.height
		updateLabelPos(timeLabel, topPos: fpsLabelBottomPos + 4)
	}

	func updateLabelPos(_ label:UILabel, topPos: CGFloat)
	{
		let inset: CGFloat = 4
		let rightPos = label.superview?.frame.size.width ?? 0
		var size = label.intrinsicContentSize
		size.width += (inset * 2);
		size.height += (inset * 2);
		let frame = CGRect(x: rightPos - size.width, y: topPos, width: size.width, height: size.height);
		label.frame = frame
	}

	var standardButtonColor: UIColor {
		get { UIColor.white }
	}

	var enabledFeatureButtonColor: UIColor {
		get { UIColor.green }
	}

	func setFeatureEnabledButtonState(_ button:UIButton?, enabled: Bool)
	{
		button?.setTitleColor(
			enabled ? enabledFeatureButtonColor : standardButtonColor,
			for: .normal
		)
	}
	
	func handleAuthorizationFailure(error: Error)
	{
		let msg = error.localizedDescription
		self.presentAuthorizationFailureMessage(msg);
	}

	func handleAuthorizationFailure(result:AuthResult?)
	{
		var errorMsg = "";
		switch (result?.status) {
			case .expired:
				errorMsg = "License expired"
				break;
				
			case .inactive:
				errorMsg = "License is inactive"
				break;
				
			default:
				break;
		}
		
		self.presentAuthorizationFailureMessage(errorMsg)
	}

	func presentAuthorizationFailureMessage(_ msg: String)
	{
		let alert = UIAlertController(title: "Authorization failed", message:msg, preferredStyle:.alert)
		let defaultAction = UIAlertAction(title:"OK", style:.default, handler: { _ in })
		alert.addAction(defaultAction)
		self.present(alert, animated: true, completion: nil)
	}

	override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
		get { .portrait }
	}
}
