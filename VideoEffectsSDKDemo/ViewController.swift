import UIKit
import AVFoundation

import TSVB

enum ColorMode {
	case none
	case correction
	case grading
	case filter
}

class ViewController: UIViewController {
	let pipelineQueue = DispatchQueue(label: "com.effectssdk.camera-pipeline");
	// The pipeline is thread-safe and needs no lock. Enabling an effect may load
	// a model though, so it is done off the main thread, in the order of taps.
	let pipelineControlQueue = DispatchQueue(label: "com.effectssdk.pipeline-control")
	let frameView = FrameView(frame: CGRect(x: 0, y: 0, width: 0, height: 0))
	lazy var fpsLabel = makeInfoLabel()
	lazy var timeLabel = makeInfoLabel()
	lazy var cpuLabel = makeInfoLabel()
	var timer: Timer? = nil
	var lastCPUTime = processCPUTime()
	var lastCPUCheck = Date()

	var blurEnabled = false
	var replaceEnabled = false
	var beautificationEnabled = false
	var portraitLightingEnabled = false
	var colorMode = ColorMode.none
	var smartZoomEnabled = false
	var lowLightEnabled = false;
	var sharpeningEnabled = false;
	var noiseSuppressionEnabled = false

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
	lazy var beautificationButton = makeFeatureButton(
		title: "Beautification",
		onTouchHandler: #selector(toggleBeautification)
	)
	lazy var portraitLightingButton = makeFeatureButton(
		title: "Portrait Lighting",
		onTouchHandler: #selector(togglePortraitLighting)
	)
	lazy var colorCorrectionButton = makeFeatureButton(
		title: "Color Correction",
		onTouchHandler: #selector(toggleColorCorrection)
	)
	lazy var colorGradingButton = makeFeatureButton(
		title: "Color Grading",
		onTouchHandler: #selector(toggleColorGrading)
	)
	lazy var colorFilterButton = makeFeatureButton(
		title: "Color Filter",
		onTouchHandler: #selector(toggleColorFilter)
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
	lazy var noiseSuppressionButton = makeFeatureButton(
		title: "Noise Suppression",
		onTouchHandler: #selector(toggleNoiseSuppression)
	)
	lazy var neuralEngineButton = makeFeatureButton(
		title: "Neural Engine",
		onTouchHandler: #selector(toggleNeuralEngine)
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
		guard let pipeline = sdkFactory.newPipeline() else {
			presentFailureMessage(title: "Failed to start", "The pipeline could not be created.")
			return
		}
		self.pipeline = pipeline
		frameFactory = sdkFactory.newFrameFactory()

		let rootView = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: 0));
		rootView.addSubview(frameView);
		frameView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

		rootView.addSubview(makeButtonPanel())

		rootView.addSubview(timeLabel)
		rootView.addSubview(fpsLabel)
		rootView.addSubview(cpuLabel)

		self.view = rootView

		let pipelineConfig = pipeline.copyConfiguration()!
		pipelineConfig.segmentationPreset = .quality
		pipeline.setConfiguration(pipelineConfig)
		setFeatureEnabledButtonState(
			neuralEngineButton,
			enabled: pipeline.copyConfiguration()!.isSegmentationOnNeuralEngineEnabled
		)

		// Effect parameters may be set before the effect is enabled.
		pipeline.colorCorrection.power = 0.5
		pipeline.colorCorrection.vibrance = 0.2
		// Darkens the background only while it is the frame itself, blurred or not:
		// not while it is replaced.
		pipeline.portraitLighting.backgroundDarkening = 0.6

		toggleReplaceBackground()

		capturer = SimpleCameraCapturer(
			queue: pipelineQueue,
			callback: {buffer in self.processFrame(buffer: buffer)}
		)
		capturer?.start()

		lastCPUTime = processCPUTime()
		lastCPUCheck = Date()
		timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) {_ in
			self.updateTimeAndFPSLabels()
		}

		UIApplication.shared.isIdleTimerDisabled = true;
	}

	func processFrame(buffer: CMSampleBuffer) {
		guard let pipeline = self.pipeline,
			  let inputFrame = CMSampleBufferGetImageBuffer(buffer) else { return }

		let startTime = Date()
		let result = pipeline.process(pixelBuffer:inputFrame, metalCompatible:true, error:nil)
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
			blurEnabled = await toggleFeature(
				blurButton,
				enabled: blurEnabled,
				enable: { pipeline in
					let error = pipeline.enableBlurBackground(power: 0.3)
					if error == .ok {
						pipeline.disableReplaceBackground()
					}
					return error
				},
				disable: { $0.disableBlurBackground() }
			)
			if blurEnabled {
				replaceEnabled = false
			}
			updateBackgroundFeatureButtons()
		}
	}

	@objc func toggleReplaceBackground()
	{
		Task {
			let factory = frameFactory
			replaceEnabled = await toggleFeature(
				replacementButton,
				enabled: replaceEnabled,
				enable: { pipeline in
					var controller = nil as ReplacementController?
					let error = pipeline.enableReplaceBackground(&controller)
					if error == .ok {
						controller?.background = loadBackgroundFrame(factory)
						pipeline.disableBlurBackground()
					}
					return error
				},
				disable: { $0.disableReplaceBackground() }
			)
			if replaceEnabled {
				blurEnabled = false
			}
			updateBackgroundFeatureButtons()
		}
	}

	@objc func toggleBeautification()
	{
		Task {
			beautificationEnabled = await toggleFeature(
				beautificationButton,
				enabled: beautificationEnabled,
				enable: { $0.enableBeautification() },
				disable: { $0.disableBeautification() }
			)
		}
	}

	@objc func togglePortraitLighting()
	{
		Task {
			portraitLightingEnabled = await toggleFeature(
				portraitLightingButton,
				enabled: portraitLightingEnabled,
				enable: { $0.enablePortraitLighting() },
				disable: { $0.disablePortraitLighting() }
			)
		}
	}

	@objc func toggleColorCorrection()
	{
		Task {
			await toggleColorMode(.correction) { $0.enableColorCorrection() }
		}
	}

	@objc func toggleColorGrading()
	{
		Task {
			let factory = frameFactory
			await toggleColorMode(.grading) { pipeline in
				guard let reference = loadBackgroundFrame(factory) else {
					return .invalidArgument
				}
				return pipeline.enableColorCorrection(withReference: reference)
			}
		}
	}

	@objc func toggleColorFilter()
	{
		Task {
			await toggleColorMode(.filter) { pipeline in
				guard let lutPath =
					Bundle.main.path(forResource: "color_filter", ofType: "cube") else {
					return .invalidArgument
				}
				return pipeline.enableColorCorrection(withLutFile: lutPath)
			}
		}
	}

	@objc func toggleSmartZoom()
	{
		Task {
			smartZoomEnabled = await toggleFeature(
				smartZoomButton,
				enabled: smartZoomEnabled,
				enable: { $0.enableSmartZoom() },
				disable: { $0.disableSmartZoom() }
			)
		}
	}

	@objc func toggleLowLight()
	{
		Task {
			lowLightEnabled = await toggleFeature(
				lowLightButton,
				enabled: lowLightEnabled,
				enable: { $0.enableLowLightAdjustment() },
				disable: { $0.disableLowLightAdjustment() }
			)
		}
	}

	@objc func toggleSharpening()
	{
		Task {
			sharpeningEnabled = await toggleFeature(
				sharpeningButton,
				enabled: sharpeningEnabled,
				enable: { $0.enableSharpening() },
				disable: { $0.disableSharpening() }
			)
		}
	}

	@objc func toggleNoiseSuppression()
	{
		Task {
			noiseSuppressionEnabled = await toggleFeature(
				noiseSuppressionButton,
				enabled: noiseSuppressionEnabled,
				enable: { $0.enableNoiseSuppression() },
				disable: { $0.disableNoiseSuppression() }
			)
		}
	}

	@objc func toggleNeuralEngine()
	{
		Task {
			guard let pipeline = self.pipeline else { return }
			neuralEngineButton.isEnabled = false
			let neuralEngineEnabled = await inControlQueue {
				let config = pipeline.copyConfiguration()!
				config.isSegmentationOnNeuralEngineEnabled =
					!config.isSegmentationOnNeuralEngineEnabled
				pipeline.setConfiguration(config)
				return pipeline.copyConfiguration()!.isSegmentationOnNeuralEngineEnabled
			}
			neuralEngineButton.isEnabled = true
			setFeatureEnabledButtonState(
				neuralEngineButton,
				enabled:neuralEngineEnabled
			)
		}
	}

	func toggleFeature(
		_ button: UIButton,
		enabled: Bool,
		enable: @escaping (Pipeline) -> PipelineError,
		disable: @escaping (Pipeline) -> Void
	) async -> Bool
	{
		guard let pipeline = self.pipeline else { return enabled }
		button.isEnabled = false
		let isEnabled = await inControlQueue {
			if enabled {
				disable(pipeline)
				return false
			}
			return enable(pipeline) == .ok
		}
		button.isEnabled = true
		setFeatureEnabledButtonState(button, enabled: isEnabled)
		return isEnabled
	}

	// Color correction, color grading and the color filter are one effect in
	// different modes: enabling one of them disables the others.
	func toggleColorMode(
		_ mode: ColorMode,
		enable: @escaping (Pipeline) -> PipelineError
	) async
	{
		guard let pipeline = self.pipeline else { return }
		let buttons = [colorCorrectionButton, colorGradingButton, colorFilterButton]
		buttons.forEach { $0.isEnabled = false }
		let disabling = colorMode == mode
		let ok = await inControlQueue {
			if disabling {
				pipeline.disableColorCorrection()
				return true
			}
			return enable(pipeline) == .ok
		}
		if ok {
			colorMode = disabling ? .none : mode
		}
		buttons.forEach { $0.isEnabled = true }
		setFeatureEnabledButtonState(colorCorrectionButton, enabled: colorMode == .correction)
		setFeatureEnabledButtonState(colorGradingButton, enabled: colorMode == .grading)
		setFeatureEnabledButtonState(colorFilterButton, enabled: colorMode == .filter)
	}

	func updateBackgroundFeatureButtons()
	{
		setFeatureEnabledButtonState(blurButton, enabled:blurEnabled)
		setFeatureEnabledButtonState(replacementButton, enabled:replaceEnabled)
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
			beautificationButton,
			portraitLightingButton,
			colorCorrectionButton,
			colorGradingButton,
			colorFilterButton,
			smartZoomButton,
			lowLightButton,
			sharpeningButton,
			noiseSuppressionButton,
			neuralEngineButton
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
			format: "%1.2f ms",
			metrics.averageTimePerFrame * 1000
		)
		timeLabel.text = timeText

		let now = Date()
		let cpuTime = processCPUTime()
		let elapsed = now.timeIntervalSince(lastCPUCheck)
		let cores = ProcessInfo.processInfo.activeProcessorCount
		let cpuUsage = (elapsed > 0) ? (cpuTime - lastCPUTime) * 100 / elapsed : 0
		lastCPUTime = cpuTime
		lastCPUCheck = now
		cpuLabel.text = String(
			format: "CPU %.0f%% (%.0f/%ld%%)",
			cpuUsage / Double(cores), cpuUsage, cores * 100
		)

		updateLabelPos(fpsLabel, topPos:38)
		let fpsLabelBottomPos =
			fpsLabel.frame.origin.y + fpsLabel.frame.size.height
		updateLabelPos(timeLabel, topPos: fpsLabelBottomPos + 4)
		let timeLabelBottomPos =
			timeLabel.frame.origin.y + timeLabel.frame.size.height
		updateLabelPos(cpuLabel, topPos: timeLabelBottomPos + 4)
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
		presentFailureMessage(title: "Authorization failed", msg)
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

		presentFailureMessage(title: "Authorization failed", errorMsg)
	}

	func presentFailureMessage(title: String, _ msg: String)
	{
		let alert = UIAlertController(title: title, message:msg, preferredStyle:.alert)
		let defaultAction = UIAlertAction(title:"OK", style:.default, handler: { _ in })
		alert.addAction(defaultAction)
		self.present(alert, animated: true, completion: nil)
	}

	override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
		get { .portrait }
	}
}

func processCPUTime() -> TimeInterval
{
	var usage = rusage()
	guard getrusage(RUSAGE_SELF, &usage) == 0 else { return 0 }
	let seconds = { (time: timeval) in Double(time.tv_sec) + Double(time.tv_usec) / 1_000_000 }
	return seconds(usage.ru_utime) + seconds(usage.ru_stime)
}

func loadBackgroundFrame(_ factory: FrameFactory?) -> Frame?
{
	let backgroundFilePath =
		Bundle.main.path(forResource: "background_image", ofType: "jpg")
	return factory?.image(withContentOfFile: backgroundFilePath)
}
