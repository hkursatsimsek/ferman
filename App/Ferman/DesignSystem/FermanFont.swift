import SwiftUI

enum FermanFont {
    static func screenTitle() -> Font {
        .custom("Archivo-SemiBold", size: 28, relativeTo: .title)
    }

    static func sectionTitle() -> Font {
        .custom("Archivo-Medium", size: 20, relativeTo: .title3)
    }

    static func orderCondition() -> Font {
        .custom("PublicSans-Regular", size: 17, relativeTo: .body)
    }

    static func orderAction() -> Font {
        .custom("PublicSans-Bold", size: 17, relativeTo: .body)
    }

    static func body() -> Font {
        .custom("PublicSans-Regular", size: 15, relativeTo: .subheadline)
    }

    static func caption() -> Font {
        .custom("PublicSans-Regular", size: 13, relativeTo: .footnote)
    }

    static func tab() -> Font {
        .custom("PublicSans-Regular", size: 15, relativeTo: .subheadline)
    }

    static func tabSelected() -> Font {
        .custom("PublicSans-Medium", size: 15, relativeTo: .subheadline)
    }

    static func buttonLabel() -> Font {
        .custom("Archivo-SemiBold", size: 17, relativeTo: .body)
    }

    static func chipLabel() -> Font {
        .custom("PublicSans-Medium", size: 13, relativeTo: .caption)
    }

    static func counter(size: CGFloat, weight: CounterWeight = .medium) -> Font {
        .custom(weight.postScriptName, size: size, relativeTo: .body)
    }

    enum CounterWeight {
        case medium
        case semibold
        case bold

        var postScriptName: String {
            switch self {
            case .medium: "ArchivoNarrow-Medium"
            case .semibold: "ArchivoNarrow-SemiBold"
            case .bold: "ArchivoNarrow-Bold"
            }
        }
    }

    /// Points of letter-spacing for roles the brief calls out explicitly (§3.3). Zero elsewhere.
    enum Tracking {
        static let screenTitle: CGFloat = -0.56
        static let sectionTitle: CGFloat = -0.20
        static let orderAction: CGFloat = 1.02
        static let chipLabel: CGFloat = 0.0
    }
}
