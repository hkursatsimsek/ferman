//
//  FontRegistrationTests.swift
//  FermanTests
//

import Testing
import UIKit

struct FontRegistrationTests {

    @Test(
        arguments: [
            "Archivo-Regular",
            "Archivo-Medium",
            "Archivo-SemiBold",
            "Archivo-Bold",
            "ArchivoNarrow-Medium",
            "ArchivoNarrow-SemiBold",
            "ArchivoNarrow-Bold",
            "PublicSans-Regular",
            "PublicSans-Medium",
            "PublicSans-Bold",
            "PublicSans-Italic",
        ])
    func fontResolves(postScriptName: String) async throws {
        #expect(UIFont(name: postScriptName, size: 12) != nil)
    }

}
