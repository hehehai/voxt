// MicrophoneCaptureSession.swift
// Captures one microphone through an input-only AUHAL, entirely off the main thread.
//
// Why not AVAudioEngine: its input node is realized against the *system default* input
// first and can only be retargeted afterwards, and on macOS the engine drives one I/O unit
// that pairs the default input with the default output (creating a private aggregate
// device when they differ). With a Bluetooth/continuity input, a closed laptop lid or an
// external display that first realization is what stalled cold starts for seconds and
// sometimes produced silent captures. An input-only HAL output unit (TN2091) is bound to
// the requested device before initialization and never touches an output device.

import Foundation
import AVFoundation
import AudioToolbox
import CoreAudio

nonisolated struct MicrophoneCaptureRequest: Sendable {
    /// `nil`, or a device that is no longer usable, captures from the system default input.
    var deviceID: AudioDeviceID?
    /// Every delivered buffer is mono Float32 at this rate, independent of the device
    /// format and of device format changes during the session.
    var outputSampleRate: Double
    /// Upper bound for the asynchronous start. Only the awaiting caller waits for it.
    var startTimeoutSeconds: Double = 10
}

nonisolated struct MicrophoneCaptureStartReport: Sendable {
    let device: AudioDeviceSnapshot
    let requestedDeviceID: AudioDeviceID?
    let usedFallbackDevice: Bool
    let deviceSampleRate: Double
    let deviceChannels: Int
    let outputSampleRate: Double
    let elapsedMs: Int
}

nonisolated enum MicrophoneCaptureEvent: Sendable {
    case firstBuffer(latencyMs: Int)
    case digitalSilence(durationMs: Int)
    case signalRecovered(afterSilenceMs: Int)
    case deviceFormatChanged(sampleRate: Double, channels: Int)
    case deviceSwitched(AudioDeviceSnapshot)
    case restartFailed(reason: String, message: String)
    case deviceLost(AudioDeviceSnapshot)
    case renderFailed(OSStatus)
}

nonisolated enum MicrophoneCaptureError: LocalizedError {
    case noInputDevice
    case audioUnit(stage: String, status: OSStatus)
    case invalidDeviceFormat(sampleRate: Double, channels: UInt32)
    case startTimedOut(seconds: Double)
    case stopped

    var errorDescription: String? {
        switch self {
        case .noInputDevice:
            return "No usable microphone input device."
        case .audioUnit(let stage, let status):
            return "Microphone audio unit failed at \(stage). status=\(status)"
        case .invalidDeviceFormat(let sampleRate, let channels):
            return "Microphone reported an unusable format. sampleRate=\(sampleRate), channels=\(channels)"
        case .startTimedOut(let seconds):
            return "Microphone did not start within \(String(format: "%.0f", seconds))s."
        case .stopped:
            return "Microphone capture was stopped before it started."
        }
    }
}

/// One microphone capture. Create a new session per recording; `stop()` is final.
///
/// Threading:
/// - All audio-unit work (create, bind, initialize, start, stop, device changes) runs on a
///   private serial control queue, so neither the main thread nor the hotkey path waits on
///   Core Audio or Bluetooth.
/// - The real-time I/O thread only renders into a preallocated buffer and hands a copy to
///   the delivery queue.
/// - `onBuffer` and `onEvent` run on the serial delivery queue. They must not wait
///   synchronously for the main thread.
nonisolated final class MicrophoneCaptureSession: @unchecked Sendable {
    typealias BufferHandler = @Sendable (AVAudioPCMBuffer) -> Void
    typealias EventHandler = @Sendable (MicrophoneCaptureEvent) -> Void

    let context: String
    private let controlQueue: DispatchQueue
    private let deliveryQueue: DispatchQueue
    private let lock = NSLock()
    private var isStopRequested = false
    private var sink: MicrophoneCaptureSink?

    // Control-queue state.
    private var inputUnit: MicrophoneInputUnit?
    private var deviceListener: MicrophoneDeviceListener?
    private var hasStarted = false

    init(context: String) {
        self.context = context
        controlQueue = DispatchQueue(label: "com.voxt.microphone.\(context).control", qos: .userInitiated)
        deliveryQueue = DispatchQueue(label: "com.voxt.microphone.\(context).delivery", qos: .userInitiated)
    }

    deinit {
        // Owners stop explicitly; this only guarantees no unit outlives the session.
        let unit = inputUnit
        let listener = deviceListener
        listener?.invalidate()
        unit?.stopAndDispose()
    }

    func start(
        _ request: MicrophoneCaptureRequest,
        onBuffer: @escaping BufferHandler,
        onEvent: @escaping EventHandler
    ) async throws -> MicrophoneCaptureStartReport {
        let sink = MicrophoneCaptureSink(
            context: context,
            queue: deliveryQueue,
            outputSampleRate: request.outputSampleRate,
            onBuffer: onBuffer,
            onEvent: onEvent
        )
        lock.lock()
        let wasStopped = isStopRequested
        if !wasStopped {
            self.sink = sink
        }
        lock.unlock()
        guard !wasStopped else { throw MicrophoneCaptureError.stopped }

        let gate = MicrophoneStartGate()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<MicrophoneCaptureStartReport, Error>) in
                gate.install(continuation)
                controlQueue.async {
                    let result: Result<MicrophoneCaptureStartReport, Error>
                    do {
                        result = .success(try self.performStart(request, sink: sink))
                    } catch {
                        result = .failure(error)
                    }
                    if !gate.resolve(result) {
                        // The caller already gave up (cancel or timeout); never leave a unit running.
                        self.teardownUnit()
                    }
                }
                if request.startTimeoutSeconds > 0 {
                    let timeout = request.startTimeoutSeconds
                    DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout) {
                        guard gate.resolve(.failure(MicrophoneCaptureError.startTimedOut(seconds: timeout))) else { return }
                        VoxtLog.audioWarning(
                            "Microphone capture start timed out. context=\(self.context), timeoutSec=\(Int(timeout)), requestedID=\(request.deviceID.map(String.init(describing:)) ?? "default")"
                        )
                        self.stop()
                    }
                }
            }
        } onCancel: {
            if gate.resolve(.failure(CancellationError())) {
                self.stop()
            }
        }
    }

    /// Moves a started capture to another device without blocking the caller. Also revives a
    /// capture whose device disappeared. If the new device cannot be prepared, the current
    /// device keeps capturing; either failure is reported as `.restartFailed`.
    func switchDevice(to deviceID: AudioDeviceID?) {
        controlQueue.async {
            guard !self.stopRequested, self.hasStarted else { return }
            self.rebuild(requestedDeviceID: deviceID, reason: "device-switch")
        }
    }

    /// Stops delivery immediately (after already captured buffers are handed out) and tears
    /// the audio unit down asynchronously, so a device stuck in start never blocks the caller.
    func stop() {
        lock.lock()
        let alreadyStopped = isStopRequested
        isStopRequested = true
        let sink = self.sink
        lock.unlock()
        guard !alreadyStopped else { return }

        sink?.close()
        controlQueue.async {
            self.teardownUnit()
        }
    }

    /// `stop()` plus waiting until the audio unit is disposed. Used at app termination.
    func stopAndWait() async {
        stop()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            controlQueue.async {
                continuation.resume()
            }
        }
    }

    private var stopRequested: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isStopRequested
    }

    // MARK: Control queue

    private func performStart(
        _ request: MicrophoneCaptureRequest,
        sink: MicrophoneCaptureSink
    ) throws -> MicrophoneCaptureStartReport {
        guard !stopRequested else { throw MicrophoneCaptureError.stopped }
        let startedAt = DispatchTime.now().uptimeNanoseconds
        var timings = MicrophoneCaptureTimings()
        let target = try resolveDevice(request.deviceID)
        let device = AudioDeviceInspector.snapshot(of: target.id)
        let lidState = LaptopLidState.current()
        timings.record("resolve", since: startedAt)
        sink.configure(deviceDescription: device.diagnosticDescription, lidState: lidState)

        let unit = try MicrophoneInputUnit.make(deviceID: target.id, sink: sink, timings: &timings)
        guard !stopRequested else {
            unit.stopAndDispose()
            throw MicrophoneCaptureError.stopped
        }
        try unit.start(timings: &timings)
        inputUnit = unit
        hasStarted = true
        registerDeviceListener(for: target.id)

        let elapsedMs = MicrophoneCaptureTimings.milliseconds(since: startedAt)
        VoxtLog.audio(
            """
            Microphone capture started. context=\(context), device=\(device.diagnosticDescription), requestedID=\(request.deviceID.map(String.init(describing:)) ?? "default"), usedFallback=\(target.usedFallback), deviceFormat=\(Int(unit.clientFormat.sampleRate))Hz/\(unit.clientFormat.channelCount)ch, output=\(Int(request.outputSampleRate))Hz/1ch, lid=\(lidState.rawValue), \(AudioDeviceInspector.describeDefaultDevices()), stepsMs=\(timings.description), totalMs=\(elapsedMs)
            """
        )

        return MicrophoneCaptureStartReport(
            device: device,
            requestedDeviceID: request.deviceID,
            usedFallbackDevice: target.usedFallback,
            deviceSampleRate: unit.clientFormat.sampleRate,
            deviceChannels: Int(unit.clientFormat.channelCount),
            outputSampleRate: request.outputSampleRate,
            elapsedMs: elapsedMs
        )
    }

    private func resolveDevice(_ requestedDeviceID: AudioDeviceID?) throws -> (id: AudioDeviceID, usedFallback: Bool) {
        if let requestedDeviceID, requestedDeviceID != AudioDeviceID(kAudioObjectUnknown) {
            if AudioDeviceInspector.isUsableInputDevice(requestedDeviceID) {
                return (requestedDeviceID, false)
            }
            VoxtLog.audioWarning(
                "Microphone capture requested device is unavailable; using the system default input. context=\(context), requestedID=\(requestedDeviceID)"
            )
        }
        guard let defaultID = AudioDeviceInspector.defaultInputDeviceID(),
              AudioDeviceInspector.isUsableInputDevice(defaultID)
        else {
            throw MicrophoneCaptureError.noInputDevice
        }
        return (defaultID, requestedDeviceID != nil)
    }

    private func rebuild(requestedDeviceID: AudioDeviceID?, reason: String) {
        guard let sink = currentSink else { return }
        let startedAt = DispatchTime.now().uptimeNanoseconds
        var timings = MicrophoneCaptureTimings()
        do {
            let target = try resolveDevice(requestedDeviceID)
            let device = AudioDeviceInspector.snapshot(of: target.id)
            let lidState = LaptopLidState.current()
            sink.configure(deviceDescription: device.diagnosticDescription, lidState: lidState)

            let replacement = try MicrophoneInputUnit.make(deviceID: target.id, sink: sink, timings: &timings)
            // Stop the old unit first so the same audio is never delivered twice.
            teardownUnit()
            guard !stopRequested else {
                replacement.stopAndDispose()
                return
            }
            try replacement.start(timings: &timings)
            inputUnit = replacement
            registerDeviceListener(for: target.id)

            VoxtLog.audio(
                "Microphone capture rebuilt. context=\(context), reason=\(reason), device=\(device.diagnosticDescription), usedFallback=\(target.usedFallback), deviceFormat=\(Int(replacement.clientFormat.sampleRate))Hz/\(replacement.clientFormat.channelCount)ch, lid=\(lidState.rawValue), stepsMs=\(timings.description), totalMs=\(MicrophoneCaptureTimings.milliseconds(since: startedAt))"
            )
            if reason == "device-switch" {
                sink.emit(.deviceSwitched(device))
            } else {
                sink.emit(
                    .deviceFormatChanged(
                        sampleRate: replacement.clientFormat.sampleRate,
                        channels: Int(replacement.clientFormat.channelCount)
                    )
                )
            }
        } catch {
            VoxtLog.audioWarning(
                "Microphone capture rebuild failed. context=\(context), reason=\(reason), error=\(error.localizedDescription), stepsMs=\(timings.description)"
            )
            sink.emit(.restartFailed(reason: reason, message: error.localizedDescription))
        }
    }

    private func registerDeviceListener(for deviceID: AudioDeviceID) {
        deviceListener?.invalidate()
        deviceListener = MicrophoneDeviceListener(deviceID: deviceID, queue: controlQueue) { [weak self] change in
            self?.handleDeviceChange(change, deviceID: deviceID)
        }
    }

    private func handleDeviceChange(_ change: MicrophoneDeviceListener.Change, deviceID: AudioDeviceID) {
        guard !stopRequested, let unit = inputUnit, unit.deviceID == deviceID else { return }
        switch change {
        case .died:
            let device = AudioDeviceInspector.snapshot(of: deviceID)
            VoxtLog.audioWarning("Microphone capture device disappeared. context=\(context), device=\(device.diagnosticDescription)")
            teardownUnit()
            currentSink?.emit(.deviceLost(device))
        case .formatChanged:
            let sampleRate = AudioDeviceInspector.nominalSampleRate(of: deviceID) ?? unit.clientFormat.sampleRate
            let channels = AudioDeviceInspector.channelCount(of: deviceID, scope: kAudioObjectPropertyScopeInput)
            let rateChanged = abs(sampleRate - unit.clientFormat.sampleRate) > 1
            let channelsChanged = channels > 0 && channels != Int(unit.clientFormat.channelCount)
            guard rateChanged || channelsChanged else { return }
            VoxtLog.audioWarning(
                "Microphone capture device format changed. context=\(context), deviceID=\(deviceID), sampleRate=\(Int(unit.clientFormat.sampleRate))->\(Int(sampleRate)), channels=\(unit.clientFormat.channelCount)->\(channels)"
            )
            rebuild(requestedDeviceID: deviceID, reason: "format-change")
        }
    }

    private var currentSink: MicrophoneCaptureSink? {
        lock.lock()
        defer { lock.unlock() }
        return sink
    }

    private func teardownUnit() {
        deviceListener?.invalidate()
        deviceListener = nil
        inputUnit?.stopAndDispose()
        inputUnit = nil
    }
}

// MARK: - Audio unit

nonisolated private final class MicrophoneInputUnit {
    let audioUnit: AudioUnit
    let deviceID: AudioDeviceID
    let clientFormat: AVAudioFormat
    private let renderBuffer: AVAudioPCMBuffer
    private let sink: MicrophoneCaptureSink
    private var isDisposed = false

    private init(
        audioUnit: AudioUnit,
        deviceID: AudioDeviceID,
        clientFormat: AVAudioFormat,
        renderBuffer: AVAudioPCMBuffer,
        sink: MicrophoneCaptureSink
    ) {
        self.audioUnit = audioUnit
        self.deviceID = deviceID
        self.clientFormat = clientFormat
        self.renderBuffer = renderBuffer
        self.sink = sink
    }

    static let renderCallback: AURenderCallback = { refCon, flags, timeStamp, busNumber, frameCount, _ in
        Unmanaged<MicrophoneInputUnit>.fromOpaque(refCon)
            .takeUnretainedValue()
            .render(flags: flags, timeStamp: timeStamp, busNumber: busNumber, frameCount: frameCount)
    }

    /// Creates, binds and initializes an input-only HAL unit. The device is selected before
    /// `AudioUnitInitialize`, so the system default input is never opened.
    static func make(
        deviceID: AudioDeviceID,
        sink: MicrophoneCaptureSink,
        timings: inout MicrophoneCaptureTimings
    ) throws -> MicrophoneInputUnit {
        var stepStartedAt = DispatchTime.now().uptimeNanoseconds
        var description = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        guard let component = AudioComponentFindNext(nil, &description) else {
            throw MicrophoneCaptureError.audioUnit(stage: "find-component", status: OSStatus(kAudioUnitErr_InvalidElement))
        }
        var instance: AudioComponentInstance?
        try check(AudioComponentInstanceNew(component, &instance), stage: "create")
        guard let audioUnit = instance else {
            throw MicrophoneCaptureError.audioUnit(stage: "create", status: OSStatus(kAudioUnitErr_InvalidElement))
        }
        timings.record("create", since: stepStartedAt)

        do {
            stepStartedAt = DispatchTime.now().uptimeNanoseconds
            var enableInput: UInt32 = 1
            try check(
                AudioUnitSetProperty(
                    audioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1,
                    &enableInput, UInt32(MemoryLayout<UInt32>.size)
                ),
                stage: "enable-input"
            )
            var disableOutput: UInt32 = 0
            try check(
                AudioUnitSetProperty(
                    audioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0,
                    &disableOutput, UInt32(MemoryLayout<UInt32>.size)
                ),
                stage: "disable-output"
            )
            var device = deviceID
            try check(
                AudioUnitSetProperty(
                    audioUnit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                    &device, UInt32(MemoryLayout<AudioDeviceID>.size)
                ),
                stage: "bind-device"
            )
            timings.record("bind", since: stepStartedAt)

            stepStartedAt = DispatchTime.now().uptimeNanoseconds
            var deviceFormat = AudioStreamBasicDescription()
            var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            try check(
                AudioUnitGetProperty(
                    audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 1,
                    &deviceFormat, &formatSize
                ),
                stage: "read-device-format"
            )
            // An input HAL unit cannot resample: the client side keeps the device rate and
            // channel count; conversion to the session format happens on the delivery queue.
            guard deviceFormat.mSampleRate.isFinite,
                  deviceFormat.mSampleRate > 0,
                  deviceFormat.mChannelsPerFrame > 0,
                  let clientFormat = AVAudioFormat(
                      commonFormat: .pcmFormatFloat32,
                      sampleRate: deviceFormat.mSampleRate,
                      channels: deviceFormat.mChannelsPerFrame,
                      interleaved: false
                  )
            else {
                throw MicrophoneCaptureError.invalidDeviceFormat(
                    sampleRate: deviceFormat.mSampleRate,
                    channels: deviceFormat.mChannelsPerFrame
                )
            }
            var clientDescription = clientFormat.streamDescription.pointee
            try check(
                AudioUnitSetProperty(
                    audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1,
                    &clientDescription, UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
                ),
                stage: "set-client-format"
            )

            var maximumFrames = max(UInt32(4096), (AudioDeviceInspector.bufferFrameSize(of: deviceID) ?? 0) * 2)
            try check(
                AudioUnitSetProperty(
                    audioUnit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0,
                    &maximumFrames, UInt32(MemoryLayout<UInt32>.size)
                ),
                stage: "set-maximum-frames"
            )
            guard let renderBuffer = AVAudioPCMBuffer(pcmFormat: clientFormat, frameCapacity: maximumFrames) else {
                throw MicrophoneCaptureError.invalidDeviceFormat(
                    sampleRate: deviceFormat.mSampleRate,
                    channels: deviceFormat.mChannelsPerFrame
                )
            }

            let inputUnit = MicrophoneInputUnit(
                audioUnit: audioUnit,
                deviceID: deviceID,
                clientFormat: clientFormat,
                renderBuffer: renderBuffer,
                sink: sink
            )
            var callback = AURenderCallbackStruct(
                inputProc: renderCallback,
                inputProcRefCon: Unmanaged.passUnretained(inputUnit).toOpaque()
            )
            try check(
                AudioUnitSetProperty(
                    audioUnit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0,
                    &callback, UInt32(MemoryLayout<AURenderCallbackStruct>.size)
                ),
                stage: "set-input-callback"
            )
            timings.record("configure", since: stepStartedAt)

            stepStartedAt = DispatchTime.now().uptimeNanoseconds
            try check(AudioUnitInitialize(audioUnit), stage: "initialize")
            timings.record("initialize", since: stepStartedAt)
            return inputUnit
        } catch {
            AudioComponentInstanceDispose(audioUnit)
            throw error
        }
    }

    func start(timings: inout MicrophoneCaptureTimings) throws {
        let startedAt = DispatchTime.now().uptimeNanoseconds
        do {
            try Self.check(AudioOutputUnitStart(audioUnit), stage: "start")
        } catch {
            stopAndDispose()
            throw error
        }
        timings.record("start", since: startedAt)
    }

    /// Safe to call more than once. `AudioOutputUnitStop` returns only after the I/O proc
    /// has finished, so the render callback can no longer reference this object afterwards.
    func stopAndDispose() {
        guard !isDisposed else { return }
        isDisposed = true
        AudioOutputUnitStop(audioUnit)
        AudioUnitUninitialize(audioUnit)
        AudioComponentInstanceDispose(audioUnit)
    }

    // Real-time I/O thread.
    private func render(
        flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
        timeStamp: UnsafePointer<AudioTimeStamp>,
        busNumber: UInt32,
        frameCount: UInt32
    ) -> OSStatus {
        guard frameCount > 0 else { return noErr }
        guard frameCount <= renderBuffer.frameCapacity else {
            let status = OSStatus(kAudioUnitErr_TooManyFramesToProcess)
            sink.reportRenderFailure(status)
            return status
        }

        let buffers = UnsafeMutableAudioBufferListPointer(renderBuffer.mutableAudioBufferList)
        let byteCount = frameCount * UInt32(MemoryLayout<Float>.size)
        for index in 0..<buffers.count {
            buffers[index].mDataByteSize = byteCount
        }
        let status = AudioUnitRender(audioUnit, flags, timeStamp, busNumber, frameCount, renderBuffer.mutableAudioBufferList)
        guard status == noErr else {
            sink.reportRenderFailure(status)
            return status
        }
        renderBuffer.frameLength = frameCount
        sink.enqueueCopy(of: renderBuffer)
        return noErr
    }

    private static func check(_ status: OSStatus, stage: String) throws {
        guard status == noErr else {
            throw MicrophoneCaptureError.audioUnit(stage: stage, status: status)
        }
    }
}

// MARK: - Delivery

/// Receives rendered buffers, converts them to the session format and reports signal
/// health. All processing state is confined to the delivery queue.
nonisolated private final class MicrophoneCaptureSink: @unchecked Sendable {
    private let context: String
    private let queue: DispatchQueue
    private let queueKey = DispatchSpecificKey<Bool>()
    private let outputFormat: AVAudioFormat
    private let onBuffer: MicrophoneCaptureSession.BufferHandler
    private let onEvent: MicrophoneCaptureSession.EventHandler
    private let requestedAt = DispatchTime.now().uptimeNanoseconds

    private let lock = NSLock()
    private var isAccepting = true
    private var deviceDescription = "unknown"
    private var lidState = LaptopLidState.unavailable
    private var hasReportedRenderFailure = false

    // Delivery-queue state.
    private var converter: AVAudioConverter?
    private var converterInputFormat: AVAudioFormat?
    private var hasReportedConversionFailure = false
    private var health = CaptureSignalHealthMonitor()
    private var hasReportedFirstBuffer = false
    private var bufferCount = 0
    private var deliveredFrameCount = 0
    private var deviceSecondsCaptured: Double = 0

    init(
        context: String,
        queue: DispatchQueue,
        outputSampleRate: Double,
        onBuffer: @escaping MicrophoneCaptureSession.BufferHandler,
        onEvent: @escaping MicrophoneCaptureSession.EventHandler
    ) {
        self.context = context
        self.queue = queue
        let sampleRate = outputSampleRate.isFinite && outputSampleRate > 0 ? outputSampleRate : 16000
        outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )!
        self.onBuffer = onBuffer
        self.onEvent = onEvent
        queue.setSpecific(key: queueKey, value: true)
    }

    func configure(deviceDescription: String, lidState: LaptopLidState) {
        lock.lock()
        self.deviceDescription = deviceDescription
        self.lidState = lidState
        lock.unlock()
    }

    // Real-time I/O thread: copy and hand off, nothing else.
    func enqueueCopy(of buffer: AVAudioPCMBuffer) {
        guard accepting else { return }
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength),
              let source = buffer.floatChannelData,
              let destination = copy.floatChannelData
        else {
            return
        }
        copy.frameLength = buffer.frameLength
        let byteCount = Int(buffer.frameLength) * MemoryLayout<Float>.size
        for channel in 0..<Int(buffer.format.channelCount) {
            memcpy(destination[channel], source[channel], byteCount)
        }
        queue.async {
            self.process(copy)
        }
    }

    func reportRenderFailure(_ status: OSStatus) {
        lock.lock()
        let shouldReport = !hasReportedRenderFailure && isAccepting
        hasReportedRenderFailure = true
        lock.unlock()
        guard shouldReport else { return }
        queue.async {
            VoxtLog.audioWarning("Microphone capture render failed. context=\(self.context), status=\(status), device=\(self.currentDeviceDescription)")
            self.deliver(.renderFailed(status))
        }
    }

    func emit(_ event: MicrophoneCaptureEvent) {
        queue.async {
            self.deliver(event)
        }
    }

    /// Hands out everything already captured, then drops later buffers and logs a summary.
    func close() {
        let finish = {
            self.lock.lock()
            let wasAccepting = self.isAccepting
            self.isAccepting = false
            self.lock.unlock()
            guard wasAccepting else { return }
            VoxtLog.audio(
                "Microphone capture stopped. context=\(self.context), device=\(self.currentDeviceDescription), buffers=\(self.bufferCount), deviceSec=\(String(format: "%.2f", self.deviceSecondsCaptured)), deliveredFrames=\(self.deliveredFrameCount), silenceSec=\(String(format: "%.2f", self.health.totalSilenceSeconds)), maxPeak=\(String(format: "%.4f", self.health.maximumPeak)), firstBuffer=\(self.hasReportedFirstBuffer)"
            )
        }
        if DispatchQueue.getSpecific(key: queueKey) == true {
            finish()
        } else {
            queue.sync(execute: finish)
        }
    }

    private var accepting: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isAccepting
    }

    private var currentDeviceDescription: String {
        lock.lock()
        defer { lock.unlock() }
        return deviceDescription
    }

    private func deliver(_ event: MicrophoneCaptureEvent) {
        guard accepting else { return }
        onEvent(event)
    }

    private func process(_ input: AVAudioPCMBuffer) {
        guard accepting, input.frameLength > 0, input.format.sampleRate > 0 else { return }
        bufferCount += 1
        let duration = Double(input.frameLength) / input.format.sampleRate
        deviceSecondsCaptured += duration
        let peak = Self.peak(of: input)

        if !hasReportedFirstBuffer {
            hasReportedFirstBuffer = true
            let latencyMs = MicrophoneCaptureTimings.milliseconds(since: requestedAt)
            VoxtLog.audio(
                "Microphone capture first buffer. context=\(context), latencyMs=\(latencyMs), frames=\(input.frameLength), deviceRate=\(Int(input.format.sampleRate)), channels=\(input.format.channelCount), peak=\(String(format: "%.4f", peak))"
            )
            onEvent(.firstBuffer(latencyMs: latencyMs))
        }

        if let healthEvent = health.observe(peak: peak, durationSeconds: duration) {
            let lid = currentLidState
            switch healthEvent {
            case .digitalSilenceDetected(let durationMs):
                VoxtLog.audioWarning(
                    "Microphone capture is delivering digital silence. context=\(context), silenceMs=\(durationMs), device=\(currentDeviceDescription), lid=\(lid.rawValue)"
                )
                onEvent(.digitalSilence(durationMs: durationMs))
            case .signalRecovered(let afterSilenceMs):
                VoxtLog.audio("Microphone capture signal recovered. context=\(context), afterSilenceMs=\(afterSilenceMs)")
                onEvent(.signalRecovered(afterSilenceMs: afterSilenceMs))
            }
        }

        guard let output = convert(input) else { return }
        deliveredFrameCount += Int(output.frameLength)
        onBuffer(output)
    }

    private var currentLidState: LaptopLidState {
        lock.lock()
        defer { lock.unlock() }
        return lidState
    }

    private func convert(_ input: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if input.format == outputFormat {
            return input
        }
        if converter == nil || converterInputFormat != input.format {
            converterInputFormat = input.format
            converter = AVAudioConverter(from: input.format, to: outputFormat)
            converter?.downmix = true
        }
        guard let converter else {
            reportConversionFailure("converter-unavailable inputRate=\(Int(input.format.sampleRate)), inputChannels=\(input.format.channelCount)")
            return nil
        }

        let ratio = outputFormat.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount((Double(input.frameLength) * ratio).rounded(.up)) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return nil }

        let provider = MicrophoneConverterInput(buffer: input)
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            guard let buffer = provider.take() else {
                inputStatus.pointee = .noDataNow
                return nil
            }
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, error == nil else {
            reportConversionFailure("status=\(status.rawValue), error=\(error?.localizedDescription ?? "nil")")
            return nil
        }
        return output.frameLength > 0 ? output : nil
    }

    private func reportConversionFailure(_ detail: String) {
        guard !hasReportedConversionFailure else { return }
        hasReportedConversionFailure = true
        VoxtLog.audioWarning("Microphone capture format conversion failed. context=\(context), \(detail)")
    }

    private static func peak(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channels = buffer.floatChannelData else { return 0 }
        let frameCount = Int(buffer.frameLength)
        var peak: Float = 0
        for channel in 0..<Int(buffer.format.channelCount) {
            let samples = channels[channel]
            for index in 0..<frameCount {
                peak = max(peak, abs(samples[index]))
            }
        }
        return peak
    }
}

/// Supplies one buffer to `AVAudioConverter` per conversion call.
nonisolated private final class MicrophoneConverterInput: @unchecked Sendable {
    private var buffer: AVAudioPCMBuffer?

    init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func take() -> AVAudioPCMBuffer? {
        defer { buffer = nil }
        return buffer
    }
}

// MARK: - Device observation

/// Observes the captured device on the control queue: disappearance and format changes
/// (for example a Bluetooth headset switching profiles mid-session).
nonisolated private final class MicrophoneDeviceListener {
    enum Change {
        case died
        case formatChanged
    }

    private struct Registration {
        var address: AudioObjectPropertyAddress
        let block: AudioObjectPropertyListenerBlock
    }

    private let deviceID: AudioDeviceID
    private let queue: DispatchQueue
    private var registrations: [Registration] = []

    init(deviceID: AudioDeviceID, queue: DispatchQueue, onChange: @escaping (Change) -> Void) {
        self.deviceID = deviceID
        self.queue = queue
        register(selector: kAudioDevicePropertyDeviceIsAlive, scope: kAudioObjectPropertyScopeGlobal) {
            if !AudioDeviceInspector.isAlive(deviceID) {
                onChange(.died)
            }
        }
        register(selector: kAudioDevicePropertyNominalSampleRate, scope: kAudioObjectPropertyScopeGlobal) {
            onChange(.formatChanged)
        }
        register(selector: kAudioDevicePropertyStreamConfiguration, scope: kAudioObjectPropertyScopeInput) {
            onChange(.formatChanged)
        }
    }

    func invalidate() {
        for var registration in registrations {
            AudioObjectRemovePropertyListenerBlock(deviceID, &registration.address, queue, registration.block)
        }
        registrations.removeAll()
    }

    private func register(
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        handler: @escaping () -> Void
    ) {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        let block: AudioObjectPropertyListenerBlock = { _, _ in handler() }
        let status = AudioObjectAddPropertyListenerBlock(deviceID, &address, queue, block)
        guard status == noErr else {
            VoxtLog.audioWarning(
                "Microphone capture could not observe device property. deviceID=\(deviceID), selector=\(AudioDeviceInspector.fourCharacterCode(selector)), status=\(status)"
            )
            return
        }
        registrations.append(Registration(address: address, block: block))
    }
}

// MARK: - Start coordination

/// Resolves the start continuation exactly once: by the control queue, a timeout, or
/// cancellation, whichever happens first.
nonisolated private final class MicrophoneStartGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<MicrophoneCaptureStartReport, Error>?
    private var pendingResult: Result<MicrophoneCaptureStartReport, Error>?
    private var isResolved = false

    func install(_ continuation: CheckedContinuation<MicrophoneCaptureStartReport, Error>) {
        lock.lock()
        if let pendingResult {
            self.pendingResult = nil
            lock.unlock()
            continuation.resume(with: pendingResult)
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    /// Returns `false` when another path already resolved the start.
    @discardableResult
    func resolve(_ result: Result<MicrophoneCaptureStartReport, Error>) -> Bool {
        lock.lock()
        guard !isResolved else {
            lock.unlock()
            return false
        }
        isResolved = true
        guard let continuation else {
            pendingResult = result
            lock.unlock()
            return true
        }
        self.continuation = nil
        lock.unlock()
        continuation.resume(with: result)
        return true
    }
}

nonisolated struct MicrophoneCaptureTimings: Sendable {
    private var steps: [(String, Int)] = []

    mutating func record(_ step: String, since startedAt: UInt64) {
        steps.append((step, Self.milliseconds(since: startedAt)))
    }

    var description: String {
        steps.isEmpty ? "none" : steps.map { "\($0.0):\($0.1)" }.joined(separator: ",")
    }

    static func milliseconds(since startedAt: UInt64) -> Int {
        let now = DispatchTime.now().uptimeNanoseconds
        guard now > startedAt else { return 0 }
        return Int((now - startedAt) / 1_000_000)
    }
}
