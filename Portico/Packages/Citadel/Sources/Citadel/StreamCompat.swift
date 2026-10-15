// iOS 16 support: AsyncStream.makeStream is only guaranteed on newer OS releases,
// so these helpers build the same (stream, continuation) pair with the classic initializer.
extension AsyncStream {
    static func makeStreamCompat(
        bufferingPolicy: Continuation.BufferingPolicy = .unbounded
    ) -> (stream: AsyncStream<Element>, continuation: AsyncStream<Element>.Continuation) {
        var captured: AsyncStream<Element>.Continuation!
        let stream = AsyncStream<Element>(bufferingPolicy: bufferingPolicy) { captured = $0 }
        return (stream, captured)
    }
}

extension AsyncThrowingStream where Failure == Error {
    static func makeStreamCompat(
        bufferingPolicy: Continuation.BufferingPolicy = .unbounded
    ) -> (stream: AsyncThrowingStream<Element, Error>, continuation: AsyncThrowingStream<Element, Error>.Continuation) {
        var captured: AsyncThrowingStream<Element, Error>.Continuation!
        let stream = AsyncThrowingStream<Element, Error>(bufferingPolicy: bufferingPolicy) { captured = $0 }
        return (stream, captured)
    }
}
