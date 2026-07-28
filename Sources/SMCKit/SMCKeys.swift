import Foundation

public enum SMCKeys {
    public static let fanCount = "FNum"
    public static let forceTest = "Ftst"

    public static func actualRPM(fan: Int) -> String { "F\(fan)Ac" }
    public static func targetRPM(fan: Int) -> String { "F\(fan)Tg" }
    public static func minimumRPM(fan: Int) -> String { "F\(fan)Mn" }
    public static func maximumRPM(fan: Int) -> String { "F\(fan)Mx" }
    public static func lowercaseMode(fan: Int) -> String { "F\(fan)md" }
    public static func uppercaseMode(fan: Int) -> String { "F\(fan)Md" }
}
