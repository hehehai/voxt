import Foundation

protocol MeetingLiveTranscribingSession: AnyObject {
    var state: MeetingLiveSessionState { get }
    func start(
        timelineOffsetSeconds: TimeInterval,
        eventHandler: @escaping @MainActor (MeetingTranscriptEvent) -> Void
    ) async throws
    func append(samples: [Float], sampleRate: Double) async
    func finish() async
    func cancel() async
}

protocol MeetingLiveSessionFactory {
    @MainActor
    func makeSession(
        for speaker: MeetingSpeaker,
        timelineOffsetSeconds: TimeInterval
    ) throws -> any MeetingLiveTranscribingSession
}
