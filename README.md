# Video Effects SDK - iOS Swift Integration Sample

This repository contains a sample Xcode project with the [Video Effects SDK](https://effectssdk.ai) integrated into it, so you can just build and run it to see the SDK in action.

This sample demonstrates how to use the [Video Effects SDK](https://effectssdk.ai). For further information, please refer to the [Video Effects SDK - iOS Swift Package](https://github.com/EffectsSDK/swift-video-effects-sdk).

## Build and run

1. Open `VideoEffectsSDKDemo.xcodeproj` in Xcode. The SDK package is fetched automatically.
2. In `VideoEffectsSDKDemo/ViewController.swift`, replace `CUSTOMER_ID` with your customer ID.
3. Select the `Video Effects SDK Demo` target, open **Signing & Capabilities** and choose your development team.
4. If Xcode reports that it failed to register the bundle identifier, change **Bundle Identifier** to one of your own, e.g. `com.yourcompany.VideoEffectsSDKDemo`.
5. Run on an iPhone or iPad: the sample needs a camera.

## Metrics

The labels in the top right corner, updated twice a second:

- **fps**: frames processed per second, over the last second. It follows the camera, at most its frame rate.
- **ms**: the average time of a `Pipeline.process` call, that is, of processing one frame with the SDK. It is not the limit of the SDK's speed and may be much higher, especially on powerful devices: between camera frames the CPU, GPU and Neural Engine are idle most of the time, so to save energy the system lowers their clocks or moves the work to the efficiency cores (E-cores). If the app does other work as well, such as video encoding, the time per frame may go down. For example, on an iPhone 17e with background replacement at 720p, a frame takes about 5.5 ms with the camera at 30 fps, but about 1.1 ms (over 900 fps) when the frames are processed one after another without pauses.
- **CPU**: the CPU usage of the whole app, `CPU 2% (12/600%)`: 2% of all cores together, and 12% of one core out of 600% for six cores, as Xcode counts.
