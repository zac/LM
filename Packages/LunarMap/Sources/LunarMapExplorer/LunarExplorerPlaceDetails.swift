import LunarMap
import SwiftUI

/// Mission summaries and remote photographs from NASA's mission pages.
/// Photos load only when this sheet opens; no image is added to the bundle.
struct LunarExplorerPlaceDetails: View {
    let place: LMLunarPOICatalog.Place
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let mission = LunarExplorerMissionFacts.forPlace(place.id) {
                        AsyncImage(url: mission.photoURL) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().scaledToFit()
                                    .accessibilityLabel("NASA photograph from " + place.name)
                            case .failure:
                                ContentUnavailableView("Photo unavailable", systemImage: "photo",
                                    description: Text("Mission facts remain available offline."))
                            default: ProgressView("Loading NASA photo").frame(height: 220)
                            }
                        }
                        .frame(maxWidth: .infinity).clipShape(RoundedRectangle(cornerRadius: 16))
                        Text("NASA").font(.footnote).foregroundStyle(.secondary)
                        LabeledContent("Launch", value: mission.launch)
                        LabeledContent("Splashdown", value: mission.splashdown)
                        Text("Crew").font(.headline)
                        Text(mission.crew)
                        Link("Mission history and photographs at NASA", destination: mission.sourceURL)
                            .hoverEffect()
                    }
                    Text(place.id == "apollo-11" ? "This coordinate uses the Apollo 11 laser reflector as its reference point. Eagle is a separate landmark." : place.blurb)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.6f°, %.6f°", place.latitude, place.longitude))
                        .monospacedDigit().textSelection(.enabled)
                    Link("Location source", destination: place.sourceURL).hoverEffect()
                }.padding(24)
            }
            .navigationTitle(place.name)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.hoverEffect() }
            }
        }.frame(width: dynamicTypeSize.isAccessibilitySize ? 720 : 560, height: 760)
    }
}

struct LunarExplorerMissionFacts {
    let launch: String
    let splashdown: String
    let crew: String
    let sourceURL: URL
    let photoURL: URL

    static func forPlace(_ id: String) -> Self? {
        let values: (String, String, String, String)
        switch id {
        case "apollo-11":
            values = ("July 16, 1969", "July 24, 1969", "Neil Armstrong, Buzz Aldrin, Michael Collins",
                "https://www.nasa.gov/wp-content/uploads/2019/07/edu_srch_celebrate_the_50th_anniversary_apollo11.jpg?w=1024")
        case "apollo-12":
            values = ("November 14, 1969", "November 24, 1969", "Charles Conrad Jr., Alan Bean, Richard Gordon Jr.",
                "https://www.nasa.gov/wp-content/uploads/2018/06/3-as12-47-6919c.jpg?w=1024")
        case "apollo-14":
            values = ("January 31, 1971", "February 9, 1971", "Alan Shepard Jr., Edgar Mitchell, Stuart Roosa",
                "https://images-assets.nasa.gov/image/as14-66-09277/as14-66-09277~large.jpg")
        case "apollo-15":
            values = ("July 26, 1971", "August 7, 1971", "David Scott, James Irwin, Alfred Worden",
                "https://www.nasa.gov/wp-content/uploads/2021/07/apollo_15_moon_landing_28_eva3_scott_w_us_flag_as15-88-11863hr.jpg?w=985")
        case "apollo-16":
            values = ("April 16, 1972", "April 27, 1972", "John Young, Charles Duke Jr., Thomas Mattingly II",
                "https://www.nasa.gov/wp-content/uploads/2017/05/s71-56246-orig.jpg?w=2048")
        case "apollo-17":
            values = ("December 7, 1972", "December 19, 1972", "Eugene Cernan, Harrison Schmitt, Ronald Evans",
                "https://www.nasa.gov/wp-content/uploads/2015/03/s72-49079.jpg?w=2048")
        default: return nil
        }
        return .init(launch: values.0, splashdown: values.1, crew: values.2,
                     sourceURL: URL(string: "https://www.nasa.gov/mission/" + id + "/")!,
                     photoURL: URL(string: values.3)!)
    }
}
