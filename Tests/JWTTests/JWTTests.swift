import JWT
import JWTKit
import XCTVapor

class JWTKitTests: XCTestCase {
    // manual authentication using req.jwt.verify
    func testManual() throws {
        // creates a new application for testing
        let app = Application(.testing)
        defer { app.shutdown() }

        // configures an es512 signer using random key
        try app.jwt.signers.use(.es512(key: .generate()))

        // jwt creation using req.jwt.sign
        app.post("login") { req -> LoginResponse in
            let credentials = try req.content.decode(LoginCredentials.self)
            return try LoginResponse(
                token: req.jwt.sign(TestUser(name: credentials.name))
            )
        }

        app.get("me") { req -> String in
            try req.jwt.verify(as: TestUser.self).name
        }

        // stores the token created during login
        var token: String?

        // test login
        try app.testable().test(
            .POST, "login", json: LoginCredentials(name: "foo")
        ) { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertContent(LoginResponse.self, res) { login in
                token = login.token
            }
        }

        guard let t = token else {
            XCTFail("login failed")
            return
        }

        // test manual authentication using req.jwt.verify
        try app.testable().test(
            .GET, "me", headers: ["authorization": "Bearer \(t)"]
        ) { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.body.string, "foo")
        }

        // create a token from a different signer
        let fakeToken = try JWTSigner.es256(key: .generate()).sign(TestUser(name: "bob"))
        try app.testable().test(
            .GET, "me", headers: ["authorization": "Bearer \(fakeToken)"]
        ) { res in
            XCTAssertEqual(res.status, .unauthorized)
        }
    }

    // test middleware-based authentication using req.auth.require
    func testMiddleware() throws {
        // creates a new application for testing
        let app = Application(.testing)
        defer { app.shutdown() }

        // configures an es512 signer using random key
        try app.jwt.signers.use(.es512(key: .generate()))

        // jwt creation using req.jwt.sign
        app.post("login") { req -> LoginResponse in
            let credentials = try req.content.decode(LoginCredentials.self)
            return try LoginResponse(
                token: req.jwt.sign(TestUser(name: credentials.name))
            )
        }

        // middleware-based authentication
        // using req.auth.require
        let secure = app.grouped(UserAuthenticator().middleware())
        secure.get("me") { req in
            try req.auth.require(TestUser.self)
        }

        // stores the token created during login
        var token: String?

        // test login
        try app.testable().test(
            .POST, "login", json: LoginCredentials(name: "foo")
        ) { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertContent(LoginResponse.self, res) { login in
                token = login.token
            }
        }

        guard let t = token else {
            XCTFail("login failed")
            return
        }

        try app.testable().test(
            .GET, "me", headers: ["authorization": "Bearer \(t)"]
        ) { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertContent(TestUser.self, res) { user in
                XCTAssertEqual(user.name, "foo")
            }
        }

        // create a token from a different signer
        let fakeToken = try JWTSigner.es256(key: .generate()).sign(TestUser(name: "bob"))
        try app.testable().test(
            .GET, "me", headers: ["authorization": "Bearer \(fakeToken)"]
        ) { res in
            XCTAssertEqual(res.status, .unauthorized)
        }
    }

    func testJWKSDownload() throws {
        // creates a new application for testing
        let app = Application(.testing)
        defer { app.shutdown() }

        app.client.configuration.ignoreUncleanSSLShutdown = true

        let google = JWKSCache(
            keyURL: "https://www.googleapis.com/oauth2/v3/certs",
            client: app.client
        )

        app.get("keys") { req in
            google.keys(on: req).map { jwks in
                jwks.keys.count
            }
        }

        try app.test(.GET, "keys") { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.body.string, "2")
        }
    }

    override func setUp() {
        XCTAssert(isLoggingConfigured)
    }
}

let isLoggingConfigured: Bool = {
    LoggingSystem.bootstrap { label in
        var handler = StreamLogHandler.standardOutput(label: label)
        handler.logLevel = .debug
        return handler
    }
    return true
}()


struct LoginResponse: Content {
    var token: String
}

struct LoginCredentials: Content {
    let name: String
}

struct TestUser: Content, Authenticatable, JWTPayload {
    var name: String

    func verify(using signer: JWTSigner) throws {
        // nothing to verify
    }
}

struct UserAuthenticator: JWTAuthenticator {
    typealias User = TestUser
    typealias Payload = TestUser

    func authenticate(jwt: TestUser, for request: Request) -> EventLoopFuture<TestUser?> {
        return request.eventLoop.makeSucceededFuture(jwt)
    }
}
