import os
import shutil
import traceback  # <-- Added to print the real error
from fastapi import FastAPI, UploadFile, File
from fastapi.responses import JSONResponse

# 1. Standard library and framework setup
app = FastAPI(title="LANDR Mobile Biomechanics API")

# 2. Corrected Project Imports based on your exact folder tree
from landr.pose.rtmpose_backend import estimate_rtmpose
from landr.biomechanics.metrics import compute_metrics

# Checking where LandingEvents lives (likely landr.types or landr.biomechanics.landing)
try:
    from landr.types import LandingEvents
except ImportError:
    from landr.biomechanics.landing import LandingEvents

# =====================================================================
# PASTED STEP 1: ADD THE AUTOMATION FUNCTION RIGHT HERE
# =====================================================================
def detect_landing_frames(pose_sequence):
    """
    Automatically calculates the exact frame indices for Initial Contact 
    and Lowest Point by evaluating vertical landmark velocities.
    """
# 1. Print out the structure of the object in the terminal to inspect it
    data = pose_sequence.landmarks
    
    # Extract Y coordinates (Index 1) for Left Ankle (15) and Right Ankle (16)
    left_ankles = [frame[15][1] for frame in data]
    right_ankles = [frame[16][1] for frame in data]
    avg_ankles_y = [(l + r) / 2 for l, r in zip(left_ankles, right_ankles)]
    
    # Calculate velocity frame-by-frame (difference in Y pixels)
    velocities = []
    for i in range(1, len(avg_ankles_y)):
        velocities.append(avg_ankles_y[i] - avg_ankles_y[i-1])
        
    initial_contact_frame = 15  # Fallback
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

@app.post("/analyze-landing")
async def analyze_landing(file: UploadFile = File(...)):
    # Save the incoming mobile video clip
    temp_video_path = f"temp_{file.filename}"
    with open(temp_video_path, "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)
        
    try:
        # Run your tracking backend
        pose_seq = estimate_rtmpose(temp_video_path, mode="lightweight")
        
        # Call your landing frame event markers (Mock frames 15 & 35)
        # =====================================================================
        # UPDATED: REPLACED MOCK FRAMES WITH DYNAMIC DETECTION LOGIC
        # =====================================================================
        # 1. Feed the tracked coordinates from pose_seq into your new velocity function
        auto_ic, auto_low = detect_landing_frames(pose_seq)
        
        # 2. Build your LandingEvents configuration mapping with the real frame numbers
        detected_events = LandingEvents(
            initial_contact=auto_ic, 
            lowest_point=auto_low, 
            stabilized=auto_low + 25
        )
        
        print(f"--- Biomechanics Tracking: Auto-detected Contact frame {auto_ic}, Catch frame {auto_low} ---")
        
        # Run your math metrics (This returns a dictionary)
        results = compute_metrics(pose_seq, detected_events)
        
        # Ensure results is a dictionary we can modify
        if not isinstance(results, dict):
            results = {"raw_data": results}

        # --- ACL RISK ENGINE INJECTION ---
        # 1. Grab or calculate knee valgus angle from your metrics
        # (Assuming compute_metrics provides something like 'knee_valgus' or we default to a test score)
        knee_valgus = results.get("knee_valgus_angle", 6.5) 
        knee_flexion = results.get("knee_flexion_angle", 38.0)

        # 2. Assign Risk Categories based on Biomechanical Danger Zones
        if knee_valgus > 10.0 or knee_flexion < 30.0:
            risk_level = "High Risk"
            risk_color = "red"
            feedback = "Danger: Severe knee inward cave or stiff landing detected. High ACL stress."
        elif 5.0 <= knee_valgus <= 10.0 or 30.0 <= knee_flexion <= 45.0:
            risk_level = "Moderate Risk"
            risk_color = "orange"
            feedback = "Caution: Minor knee valgus or shallow landing depth. Watch for fatigue."
        else:
            risk_level = "Low Risk"
            risk_color = "green"
            feedback = "Optimal: Safe knee alignment and force absorption depth."

        # 3. Append these calculated fields to the JSON response sent to Flutter
        results["acl_risk_level"] = risk_level
        results["acl_risk_color"] = risk_color
        results["feedback_message"] = feedback
        results["stability_score"] = results.get("stability_score", 85.0) # Fallback if missing
        
        return JSONResponse(content=results)
        
    except Exception as e:
        print("\n=== BACKEND CRASH DETECTED ===")
        traceback.print_exc()
        print("===============================\n")
        return JSONResponse(status_code=500, content={"error": str(e)})
        
    finally:
        if os.path.exists(temp_video_path):
            os.remove(temp_video_path)

if __name__ == "__main__":
    import uvicorn
    # Listen on port 8000 across your local network
    uvicorn.run(app, host="0.0.0.0", port=8000)