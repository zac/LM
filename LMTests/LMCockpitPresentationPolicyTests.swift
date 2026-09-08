import RealityKit
import Testing
@testable import LM

@Suite(.serialized)
struct LMCockpitPresentationPolicyTests {
    @Test func historicalDefaultHidesAllSyntheticOverlays() {
        let policy = LMCockpitPresentationPolicy()
        #expect(!policy.showsCueOverlay)
        #expect(!policy.showsCalledAngle)
        #expect(!policy.showsEyeAlignment)
        #expect(!policy.usesDiagnosticPaneColors)
        #expect(policy.landingPointHint(angleDegrees: 47, windowClosed: false, redesignationEnabled: false)
                == "DSKY N64 · press PRO to enable ACA redesignation")
    }

    @Test func eyeDiagnosticRequiresSeparateOptInAndTrainingOffClearsIt() {
        var policy = LMCockpitPresentationPolicy()
        policy.toggleEyeAlignment()
        #expect(!policy.showsEyeAlignment)
        policy.toggleTraining()
        #expect(policy.showsCueOverlay && policy.showsCalledAngle)
        #expect(!policy.showsEyeAlignment)
        #expect(policy.landingPointHint(angleDegrees: 47, windowClosed: false, redesignationEnabled: true)
                == "Training LPD 47° · ACA redesignation enabled")
        policy.toggleEyeAlignment()
        #expect(policy.usesDiagnosticPaneColors)
        policy.toggleTraining()
        #expect(policy == LMCockpitPresentationPolicy())
        policy.toggleTraining()
        #expect(!policy.showsEyeAlignment)
    }

    @Test @MainActor func sceneRecenterPreservesHiddenMarkerAndImportedOwnership() {
        let station = LMCommanderStationScene(loadACA: false)
        let marks = LMCommanderStationAssembly.descendants(station.root).filter {
            $0.name.hasPrefix("LPD ") || $0.name == "LPD_Inner" || $0.name == "LPD_Outer"
        }
        #expect(marks.count == 26)
        #expect(marks.compactMap { ($0 as? ModelEntity)?.model?.materials.first }.allSatisfy { $0 is SimpleMaterial })
        station.setLandingPointCalledAngle(47, trainingOverlayVisible: true)
        #expect(station.landingPointCalledAngleMarker.isEnabled)
        station.setLandingPointMarkingOwner(.importedWindows)
        #expect(!station.landingPointCalledAngleMarker.isEnabled)
        station.setLandingPointCalledAngle(47, trainingOverlayVisible: true)
        #expect(!station.landingPointCalledAngleMarker.isEnabled)
        station.setLandingPointDiagnosticColors(true)
        #expect(marks.compactMap { ($0 as? ModelEntity)?.model?.materials.first }.allSatisfy { $0 is UnlitMaterial })
        station.recenterAtCurrentHeadPose()
        #expect(!station.landingPointCalledAngleMarker.isEnabled)
        #expect(marks.allSatisfy { !$0.isEnabled })
        station.setLandingPointDiagnosticColors(false)
        station.setLandingPointMarkingOwner(.appGenerated)
        #expect(marks.allSatisfy { $0.isEnabled })
        #expect(!station.landingPointCalledAngleMarker.isEnabled)
        station.setLandingPointCalledAngle(47, trainingOverlayVisible: true)
        #expect(station.landingPointCalledAngleMarker.isEnabled)
        station.setLandingPointCalledAngle(47, trainingOverlayVisible: false)
        #expect(!station.landingPointCalledAngleMarker.isEnabled)
        station.setLandingPointCalledAngle(nil, trainingOverlayVisible: true)
        #expect(!station.landingPointCalledAngleMarker.isEnabled)
    }

    @Test func validationFlagsNeverImplicitlyEnableTraining() {
        #expect(LMCockpitPresentationPolicy.validation(arguments: []) == LMCockpitPresentationPolicy())
        #expect(!LMCockpitPresentationPolicy.validation(arguments: ["--cockpit-eye-alignment"]).showsEyeAlignment)
        #expect(LMCockpitPresentationPolicy.validation(arguments: ["--cockpit-training-overlays", "--cockpit-eye-alignment"]).showsEyeAlignment)
    }
}
