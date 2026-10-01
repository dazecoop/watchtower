import SwiftUI

/// The Claude logomark, converted from its SVG into normalised path commands
/// so the app keeps drawing everything in code and ships no image resources.
///
/// Coordinates are absolute, already scaled into a 0…1 square, and limited to
/// move / line / curve / close — the original's elliptical arcs were flattened
/// to cubics during conversion.
struct ClaudeMark: Shape {
    func path(in rect: CGRect) -> Path {
        // Aspect-fit the unit square into whatever we are given.
        let side = min(rect.width, rect.height)
        let originX = rect.minX + (rect.width - side) / 2
        let originY = rect.minY + (rect.height - side) / 2

        var path = Path()
        var index = 0
        let tokens = Self.commands

        func point() -> CGPoint {
            let x = CGFloat(Double(tokens[index]) ?? 0)
            let y = CGFloat(Double(tokens[index + 1]) ?? 0)
            index += 2
            return CGPoint(x: originX + x * side, y: originY + y * side)
        }

        while index < tokens.count {
            let command = tokens[index]
            index += 1
            switch command {
            case "M": path.move(to: point())
            case "L": path.addLine(to: point())
            case "C":
                let c1 = point(), c2 = point(), end = point()
                path.addCurve(to: end, control1: c1, control2: c2)
            case "Z": path.closeSubpath()
            default: break
            }
        }
        return path
    }

    // Split on any whitespace: the data is wrapped across lines below, and
    // splitting on spaces alone leaves newlines glued to the tokens either
    // side of each break, which parse as zero and drag stray edges to the
    // origin.
    private static let commands: [String] = raw
        .split(whereSeparator: \.isWhitespace)
        .map(String.init)

    private static let raw = """
        M 0.1962 0.6648 L 0.3929 0.5545 L 0.3962 0.5449 L 0.3929 0.5396 L 0.3833 0.5396 L 0.3504
        0.5376 L 0.2380 0.5345 L 0.1405 0.5305 L 0.0461 0.5254 L 0.0223 0.5204 L 0.0000 0.4910 L
        0.0023 0.4763 L 0.0223 0.4630 L 0.0509 0.4655 L 0.1142 0.4697 L 0.2091 0.4763 L 0.2780
        0.4804 L 0.3800 0.4910 L 0.3962 0.4910 L 0.3985 0.4845 L 0.3929 0.4804 L 0.3886 0.4763 L
        0.2904 0.4098 L 0.1840 0.3395 L 0.1284 0.2990 L 0.0982 0.2785 L 0.0830 0.2593 L 0.0765
        0.2173 L 0.1038 0.1872 L 0.1405 0.1897 L 0.1499 0.1922 L 0.1871 0.2208 L 0.2666 0.2823 L
        0.3704 0.3587 L 0.3856 0.3714 L 0.3916 0.3671 L 0.3924 0.3640 L 0.3856 0.3526 L 0.3291
        0.2507 L 0.2689 0.1470 L 0.2420 0.1040 L 0.2350 0.0782 C 0.2323 0.0683 0.2308 0.0581 0.2306
        0.0478 L 0.2618 0.0056 L 0.2790 0.0000 L 0.3205 0.0056 L 0.3380 0.0207 L 0.3638 0.0797 L
        0.4056 0.1725 L 0.4704 0.2988 L 0.4894 0.3362 L 0.4995 0.3709 L 0.5033 0.3815 L 0.5099
        0.3815 L 0.5099 0.3754 L 0.5152 0.3043 L 0.5251 0.2170 L 0.5347 0.1047 L 0.5380 0.0731 L
        0.5537 0.0352 L 0.5848 0.0147 L 0.6091 0.0263 L 0.6291 0.0549 L 0.6263 0.0734 L 0.6144
        0.1505 L 0.5911 0.2715 L 0.5760 0.3524 L 0.5848 0.3524 L 0.5949 0.3423 L 0.6360 0.2879 L
        0.7048 0.2019 L 0.7352 0.1677 L 0.7706 0.1300 L 0.7934 0.1121 L 0.8365 0.1121 L 0.8681
        0.1591 L 0.8540 0.2077 L 0.8096 0.2638 L 0.7729 0.3114 L 0.7203 0.3822 L 0.6873 0.4389 L
        0.6904 0.4435 L 0.6982 0.4427 L 0.8172 0.4174 L 0.8815 0.4057 L 0.9582 0.3926 L 0.9929
        0.4088 L 0.9967 0.4252 L 0.9830 0.4589 L 0.9010 0.4791 L 0.8048 0.4984 L 0.6615 0.5322 L
        0.6598 0.5335 L 0.6618 0.5360 L 0.7263 0.5421 L 0.7539 0.5436 L 0.8215 0.5436 L 0.9473
        0.5530 L 0.9802 0.5747 L 1.0000 0.6013 L 0.9967 0.6215 L 0.9461 0.6474 L 0.8777 0.6312 L
        0.7182 0.5932 L 0.6635 0.5795 L 0.6560 0.5795 L 0.6560 0.5841 L 0.7015 0.6286 L 0.7851
        0.7040 L 0.8896 0.8011 L 0.8949 0.8252 L 0.8815 0.8442 L 0.8673 0.8421 L 0.7755 0.7731 L
        0.7400 0.7420 L 0.6598 0.6745 L 0.6544 0.6745 L 0.6544 0.6815 L 0.6729 0.7086 L 0.7706
        0.8553 L 0.7757 0.9003 L 0.7686 0.9150 L 0.7433 0.9239 L 0.7155 0.9188 L 0.6582 0.8386 L
        0.5992 0.7483 L 0.5516 0.6673 L 0.5458 0.6707 L 0.5177 0.9729 L 0.5045 0.9883 L 0.4742
        1.0000 L 0.4489 0.9808 L 0.4355 0.9497 L 0.4489 0.8882 L 0.4651 0.8080 L 0.4782 0.7443 L
        0.4901 0.6651 L 0.4972 0.6388 L 0.4967 0.6370 L 0.4909 0.6378 L 0.4311 0.7197 L 0.3403
        0.8424 L 0.2684 0.9193 L 0.2511 0.9261 L 0.2212 0.9107 L 0.2240 0.8831 L 0.2407 0.8586 L
        0.3402 0.7321 L 0.4002 0.6537 L 0.4390 0.6084 L 0.4387 0.6018 L 0.4365 0.6018 L 0.1722
        0.7733 L 0.1251 0.7794 L 0.1048 0.7604 L 0.1073 0.7293 L 0.1170 0.7192 L 0.1965 0.6645 L
        0.1962 0.6648 Z
        """
}
