/// Center during a drag is spring return, not an UP command. A deliberate
/// center tap (no upper/lower excursion) is the host gesture for selecting UP.
enum LMEventTimerControlRouting {
    static func command(id: String, position: Int, explicitCenterSelection: Bool = false) -> LMEventTimerState.Command? {
        guard (0...2).contains(position) else { return nil }
        switch id {
        case "EventTimer_ResetCount":
            if position == 0 { return .reset }
            if position == 2 { return .selectDirection(.down) }
            return explicitCenterSelection ? .selectDirection(.up) : nil
        case "EventTimer_TimerControl": return position == 0 ? .start : position == 2 ? .stop : nil
        case "EventTimer_MinutesSlew": return .minuteSlew(position == 1 ? nil : position == 0 ? .tens : .units)
        case "EventTimer_SecondsSlew": return .secondSlew(position == 1 ? nil : position == 0 ? .tens : .units)
        default: return nil
        }
    }
}
