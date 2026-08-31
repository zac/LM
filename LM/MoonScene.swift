//
//  MoonScene.swift
//  LM
//
//  Created by Zac White on 1/26/25.
//

import Foundation
import CoreLocation
import RealityKit
import RealityKitContent

class MoonScene: Entity {
    required init() {
        super.init()
        Task {
            let scene = try await Entity(named: "Immersive", in: realityKitContentBundle)
            self.addChild(scene)
        }
    }
}

struct LunarCoordinates {
    let latitude: CLLocationDegrees
    let longitude: CLLocationDegrees
}

struct EarthMoonSystem {
    static let moonRadius = LMSelenographicCoordinateSystem.meanEarthPolarRadiusMeters
    static let earthMoonDistance: Double = 384400000.0 // meters

    static func earthPosition(relativeToMoon moonPosition: SIMD3<Double>) -> SIMD3<Double>  {
        return moonPosition + [earthMoonDistance, 0, 0]
    }
}

//extension LunarCoordinates {
//    func toCartesianCoordinates() -> any SIMD<Double> {
//        let latRad = latitude * .pi / 180
//        let lonRad = longitude * .pi / 180
//
//        let x = EarthMoonSystem.moonRadius * sin(latRad) * cos(lonRad)
//        let y = EarthMoonSystem.moonRadius * cos(latRad)
//        let z = EarthMoonSystem.moonRadius * sin(lonRad) * sin(latRad)
//
//        return SIMD<Double>(x, y, z)
//    }
//}
//
//// Example usage:
//let apollo11LandingSite = LunarCoordinates(latitude: 0.6735, longitude: 23.4815)
//let landingPosition = apollo11LandingSite.toCartesianCoordinates()
//print("Apollo 11 landing site position: $landingPosition)")
