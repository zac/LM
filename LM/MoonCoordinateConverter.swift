//
//  for.swift
//  LM
//
//  Created by Zac White on 1/27/25.
//


import Foundation
import RealityKit
import simd

/// A utility class for converting real lunar coordinates (lat/long/alt)
/// into local RealityKit coordinates.
struct MoonCoordinateConverter {
    
    /// Mean radius of the Moon in kilometers.
    static let lunarMeanRadius: Double = 1737.4
    
    /// Converts selenographic coordinates (latitude, longitude, altitude)
    /// to a local position (x, y, z) in meters or kilometers, depending on your scale.
    ///
    /// - Parameters:
    ///   - latitudeDeg: Latitude in degrees (0 = equator, +north, -south).
    ///   - longitudeDeg: Longitude in degrees (0 = prime meridian, +east, -west).
    ///   - altitude: Altitude above the lunar surface in kilometers.
    ///   - scale: A scaling factor to convert real kilometers into
    ///            whatever unit you use in your scene. 
    ///            e.g., 1.0 for 1:1 in kilometers, or 0.001 for meters, etc.
    ///
    /// - Returns: A `SIMD3<Float>` position in your local RealityKit coordinate space.
    static func latitudeLongitudeAltitudeToPosition(
        latitudeDeg: Double,
        longitudeDeg: Double,
        altitude: Double,
        scale: Double
    ) -> SIMD3<Float> {
        
        // Convert degrees to radians
        let lat = latitudeDeg * .pi / 180.0
        let lon = longitudeDeg * .pi / 180.0
        
        // Radius from center of Moon
        let r = (lunarMeanRadius + altitude) // in km
        
        // Compute local cartesian
        // Using Y-up, X-east, Z-??? We'll place east in +X, north in +Y, negative Z for increasing east longitude.
        let x = r * cos(lat) * cos(lon)
        let y = r * sin(lat)                  // north pole => +Y
        let z = -r * cos(lat) * sin(lon)      // negative Z to handle east-positive long

        // Apply scale (e.g. to convert km to scene units)
        let scaledX = x * scale
        let scaledY = y * scale
        let scaledZ = z * scale
        
        // Convert to Float for RealityKit's SIMD3<Float>
        return SIMD3<Float>(Float(scaledX), Float(scaledY), Float(scaledZ))
    }
    
    /// Converts orbital/inertial coordinates from NASA data
    /// (if you have an Earth-Moon or ECI-like system) into the local
    /// frame of reference. This method is a placeholder for more
    /// advanced conversions. 
    ///
    /// - Parameters:
    ///   - positionInInertialFrame: The spacecraft position in some inertial system (e.g. J2000).
    ///   - transformToLocal: A transform (rotation + translation) that orients NASA's inertial coords
    ///                       such that the Moon center is (0,0,0) and axes align with your local space.
    /// - Returns: Local coordinates as `SIMD3<Float>` for RealityKit.
    static func inertialToLocalPosition(
        positionInInertialFrame: SIMD3<Double>,
        transformToLocal: simd_float4x4
    ) -> SIMD3<Float> {
        
        let pos = simd_double4(positionInInertialFrame, 1.0)
        let localPosD = simd_mul(transformToLocal, simd_float4(Float(pos.x), Float(pos.y), Float(pos.z), 1.0))
        return SIMD3<Float>(localPosD.x, localPosD.y, localPosD.z)
    }
    
}