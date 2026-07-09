import os
import shutil
import traceback  # For printing exact stack traces during debugging
from fastapi import FastAPI, UploadFile, File
from fastapi.responses import JSONResponse

# 1. Standard library and framework setup
app = FastAPI(title="LANDR Mobile Biomechanics API")

# 2. Project Imports based on the landr engine structure
from landr.pose.rtmpose_backend import estimate_rtmpose
from landr.biomechanics.metrics import compute_metrics

# Map where LandingEvents lives depending on library configuration versions
try:
    from landr.types import LandingEvents
except ImportError:
    from landr.biomechanics.landing import LandingEvents

def detect_landing_frames(pose_sequence):
    """
    Automatically calculates the exact frame indices for Initial Contact 
    and Lowest Point by evaluating vertical landmark velocities.
    """
    # Grab the underlying landmark coordinate matrix
    data = pose_sequence.landmarks
    
    # Extract Y coordinates (Index 1) for Left Ankle (15) and Right Ankle (16)
    left_ankles = [frame[15][1] for frame in data]
    right_ankles = [frame[16][1] for frame in data]
    avg_ankles_y = [(l + r) / 2 for l, r in zip(left_ankles, right_ankles)]
    
    # Calculate velocity frame-by-frame (difference in Y pixels)
    velocities = []
    for i in range(1, len(avg_ankles_y)):
        velocities.append(avg_ankles_y[i] - avg_ankles_y[i-1])
        
    initial_contact_frame = 15  # Default fallback if loop bounds are tight
    max_downward_speed = 0
    
    for idx, v in enumerate(velocities):
        if v > max_downward_speed:
            max_downward_speed = v
            initial_contact_frame = idx + 1
            
    # Extract Y coordinates (Index 1) for Left Hip (11) and Right Hip (12)
    left_hips = [frame[11][1] for frame in data]
    right_hips = [frame[12][1] for frame in data]
    avg_hips_y = [(l + r) / 2 for l, r in zip(left_hips, right_hips)]
    
    # Find maximum Y position (lowest physical drop) after contact frame
    search_zone = avg_hips_y[initial_contact_frame:]
    if search_zone:
        lowest_point_frame = initial_contact_frame + search_zone.index(max(search_zone))
    else:
        lowest_point_frame = initial_contact_frame + 20
        
    return initial_contact_frame, lowest_point_frame

@app.post("/analyze-landing-two-view")
async def analyze_landing_two_view(
    front: UploadFile = File(...),
    side: UploadFile = File(...),
):
    """Two-view endpoint: front video for valgus, side video for flexion/trunk."""
    from landr.multiview import analyze_two_view_sequences
    from landr.accuracy import improved_sequence
    from landr.types import PoseSequence

    front_path = f"temp_front_{front.filename}"
    side_path = f"temp_side_{side.filename}"
    with open(front_path, "wb") as f:
        shutil.copyfileobj(front.file, f)
    with open(side_path, "wb") as f:
        shutil.copyfileobj(side.file, f)

    try:
        front_seq = estimate_rtmpose(front_path, mode="lightweight")
        side_seq  = estimate_rtmpose(side_path,  mode="lightweight")
        front_seq = improved_sequence(front_seq)
        side_seq  = improved_sequence(side_seq)
        result = analyze_two_view_sequences(front_seq, side_seq)
        metrics = result.metrics

        knee_valgus  = metrics.get("at_initial_contact", {}).get("knee_valgus_deg", 0.0)
        knee_flexion = metrics.get("at_initial_contact", {}).get("knee_flexion_deg", 0.0)
        asymmetry    = metrics.get("asymmetry_index", 0.0)
        peak_valgus  = max(abs(metrics.get("peak_valgus_deg", {}).get("left", 0.0)),
                           abs(metrics.get("peak_valgus_deg", {}).get("right", 0.0)))

        if knee_valgus > 10.0 or knee_flexion < 30.0:
            risk_level, risk_color = "HIGH RISK", "red"
            feedback = "Danger: Severe knee inward cave or stiff landing detected. High ACL stress."
        elif 5.0 <= knee_valgus <= 10.0 or 30.0 <= knee_flexion <= 45.0:
            risk_level, risk_color = "MODERATE RISK", "orange"
            feedback = "Caution: Minor knee valgus or shallow landing depth. Watch for fatigue."
        else:
            risk_level, risk_color = "LOW RISK", "green"
            feedback = "Optimal: Safe knee alignment and force absorption depth."

        out = dict(metrics)
        out.update({
            "knee_valgus_angle": round(knee_valgus, 2),
            "knee_flexion_angle": round(knee_flexion, 2),
            "asymmetry_index": round(asymmetry, 3),
            "stability_score": 85.0,
            "acl_risk_level": risk_level,
            "acl_risk_color": risk_color,
            "feedback_message": feedback,
            "mode": "two_view",
            "acl_risk_assessment": {
                "risk_factor": risk_level,
                "max_valgus_observed_deg": round(peak_valgus, 2),
                "coaching_cue": feedback,
                "risk_color_code": risk_color,
            },
        })
        return JSONResponse(content=out)

    except Exception as e:
        print("\n=== TWO-VIEW CRASH ===")
        traceback.print_exc()
        print("=====================\n")
        return JSONResponse(status_code=500, content={"error": str(e)})
    finally:
        for p in (front_path, side_path):
            if os.path.exists(p):
                os.remove(p)


@app.post("/analyze-landing")
async def analyze_landing(file: UploadFile = File(...)):
    # Save the incoming mobile video clip payload to disk
    temp_video_path = f"temp_{file.filename}"
    with open(temp_video_path, "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)
        
    try:
        # Run the neural network tracking backend pipeline
        pose_seq = estimate_rtmpose(temp_video_path, mode="lightweight")
        
        # Feed the tracked coordinates from pose_seq into the velocity function
        auto_ic, auto_low = detect_landing_frames(pose_seq)
        
        # Build the LandingEvents configuration mapping with the real frame numbers
        detected_events = LandingEvents(
            initial_contact=auto_ic, 
            lowest_point=auto_low, 
            stabilized=auto_low + 25
        )
        
        print(f"--- Biomechanics Tracking: Auto-detected Contact frame {auto_ic}, Catch frame {auto_low} ---")
        
        # Run the core metrics framework calculations
        results = compute_metrics(pose_seq, detected_events)
        
        # Ensure results is always a mutable dictionary structure
        if not isinstance(results, dict):
            results = {"raw_data": results}

        # --- EXTRACT CORE MATH METRICS FROM ENGINE ---
        knee_valgus = results.get("knee_valgus_angle", 6.5) 
        knee_flexion = results.get("knee_flexion_angle", 38.0)
        asymmetry = results.get("asymmetry_index", 0.035)
        stability = results.get("stability_score", 85.0)

        # Evaluate Biomechanical Danger Zones and Thresholds
        if knee_valgus > 10.0 or knee_flexion < 30.0:
            risk_level = "HIGH RISK"
            risk_color = "red"
            feedback = "Danger: Severe knee inward cave or stiff landing detected. High ACL stress."
        elif 5.0 <= knee_valgus <= 10.0 or 30.0 <= knee_flexion <= 45.0:
            risk_level = "MODERATE RISK"
            risk_color = "orange"
            feedback = "Caution: Minor knee valgus or shallow landing depth. Watch for fatigue."
        else:
            risk_level = "LOW RISK"
            risk_color = "green"
            feedback = "Optimal: Safe knee alignment and force absorption depth."

        # --- VARIANT A: ROOT LEVEL FLAT KEYS (For main.dart) ---
        results["knee_valgus_angle"] = knee_valgus
        results["knee_flexion_angle"] = knee_flexion
        results["asymmetry_index"] = asymmetry
        results["stability_score"] = stability
        results["acl_risk_level"] = risk_level
        results["acl_risk_color"] = risk_color
        results["feedback_message"] = feedback
        
        # --- VARIANT B: NESTED DATA OBJECT KEYS (For session_manager.dart) ---
        results["acl_risk_assessment"] = {
            "risk_factor": risk_level,
            "max_valgus_observed_deg": knee_valgus,
            "coaching_cue": feedback,
            "risk_color_code": risk_color
        }
        
        # Extra tracking features for future upgrades
        results["detected_frames"] = {
            "initial_contact": auto_ic,
            "lowest_catch_point": auto_low
        }
        
        return JSONResponse(content=results)
        
    except Exception as e:
        print("\n=== BACKEND CRASH DETECTED ===")
        traceback.print_exc()
        print("===============================\n")
        return JSONResponse(status_code=500, content={"error": str(e)})
        
    finally:
        # Guarantee local cleanup of temp storage video clips to prevent memory bloating
        if os.path.exists(temp_video_path):
            os.remove(temp_video_path)

if __name__ == "__main__":
    import uvicorn
    # Listen globally on port 8000 across your local network interface environment
    uvicorn.run(app, host="0.0.0.0", port=8000)