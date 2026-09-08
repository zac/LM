/// Actions supplied by the containing app. The standalone Moon app has no cockpit.
public struct LunarExplorerHostActions {
    public var close: (() -> Void)?
    public var landInCockpit: (() -> Void)?
    public var cockpitDisplayName: String

    public init(close: (() -> Void)? = nil, landInCockpit: (() -> Void)? = nil,
                cockpitDisplayName: String = "cockpit") {
        self.close = close
        self.landInCockpit = landInCockpit
        self.cockpitDisplayName = cockpitDisplayName
    }
}
