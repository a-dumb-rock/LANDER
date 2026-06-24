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
        detected_events = LandingEvents(initial_contact=15, lowest_point=35, stabilized=60)
        
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