import XCTest
@testable import Voxt

final class ModelLogoKeyTests: XCTestCase {
    func testNemotronASRUsesNvidiaLogo() {
        XCTAssertEqual(
            ModelLogoKey.resolve(title: "Nemotron 0.6B (8bit)", engine: "MLX Audio"),
            .nvidia
        )
    }
}
