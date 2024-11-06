
import Foundation

class Metrics
{
	let expirationTimeSecs: TimeInterval = 1
	var cameraFrameTimes: Array<Date> = []
	var intervals: Array<DateInterval> = []
	
func didCameraFrame(_ frameDate:Date)
{
	while(cameraFrameTimes.count > 0) {
		let date = cameraFrameTimes.first!
		if (frameDate.timeIntervalSince(date) > expirationTimeSecs) {
			cameraFrameTimes.remove(at: 0)
		}
		else {
			break
		}
	}
	cameraFrameTimes.append(frameDate)
}
	
func didProcessFrame(for interval: DateInterval)
{
	let lastDate = interval.start;
	while(intervals.count > 0) {
		let date = intervals.first!.start;
		if (lastDate.timeIntervalSince(date) > expirationTimeSecs) {
			intervals.remove(at: 0)
		}
		else {
			break;
		}
	}

	intervals.append(interval)
}
	
var averageTimePerFrame: TimeInterval
{
	if (intervals.isEmpty) {
		return 0;
	}
	
	var sum: TimeInterval = 0;
	for interval in intervals {
		sum += interval.duration;
	}

	return sum / TimeInterval(intervals.count);
}
	
var cameraFPS: Double
{
	if (cameraFrameTimes.count < 2) {
		return 0;
	}

	var prevFrameTime = cameraFrameTimes.first!;
	var intervalSum: TimeInterval = 0;
	var intervalCount = 0;

	for frameTime in cameraFrameTimes {
		if (frameTime == prevFrameTime) {
			continue;
		}

		intervalSum += frameTime.timeIntervalSince(prevFrameTime)
		intervalCount += 1;
		prevFrameTime = frameTime;
	}

	if (0 == intervalCount) {
		return 0;
	}

	return 1.0 / (Double(intervalSum) / Double(intervalCount));
}
	
}
