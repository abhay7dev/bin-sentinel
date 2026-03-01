import { useRef, useState, useEffect, useCallback } from "react";
import axios from "axios";
import * as tf from "@tensorflow/tfjs";
import * as cocoSsd from "@tensorflow-models/coco-ssd";
import CitySelector from "./CitySelector";
import { ResultOverlay } from "./ResultCard";
import { useClosestCity } from "./hooks/useClosestCity";

const API_URL = import.meta.env.VITE_API_URL || "http://localhost:8000";

const STATES = { LOADING: "LOADING", IDLE: "IDLE", DETECTED: "DETECTED", SCANNING: "SCANNING", COOLDOWN: "COOLDOWN" };
const DETECT_INTERVAL_MS = 300;
const STABLE_FRAMES_NEEDED = 1;
const COOLDOWN_MS = 2000;
/** Fallback: trigger scan after this long in DETECTED if stability didn’t fire first. */
const DETECTED_TRIGGER_MS = 500;
const CAPTURE_WIDTH = 640;
const SCAN_TIMEOUT_MS = 45000;
const MIN_SCORE = 0.35;
const LERP_FACTOR = 0.7;
const IOU_THRESHOLD = 0.2;
const IGNORED_CLASSES = new Set(["person"]);
const MAX_MISS_FRAMES = 8;

// Motion fallback for objects COCO-SSD can't recognize
const MOTION_FALLBACK_FRAMES = 8;
const MOTION_DIFF_THRESHOLD = 12;
const MOTION_STABLE_FRAMES = 2;
const MOTION_SCAN_STEP = 6;

function normalizeBbox(bbox, videoW, videoH) {
  const [x, y, w, h] = bbox;
  return {
    x: x / videoW,
    y: y / videoH,
    w: w / videoW,
    h: h / videoH,
  };
}

function lerpBox(current, target, factor) {
  return {
    x: current.x + (target.x - current.x) * factor,
    y: current.y + (target.y - current.y) * factor,
    w: current.w + (target.w - current.w) * factor,
    h: current.h + (target.h - current.h) * factor,
  };
}

function computeIoU(a, b) {
  const ax2 = a.x + a.w, ay2 = a.y + a.h;
  const bx2 = b.x + b.w, by2 = b.y + b.h;
  const ix = Math.max(0, Math.min(ax2, bx2) - Math.max(a.x, b.x));
  const iy = Math.max(0, Math.min(ay2, by2) - Math.max(a.y, b.y));
  const inter = ix * iy;
  const union = a.w * a.h + b.w * b.h - inter;
  return union > 0 ? inter / union : 0;
}

/**
 * Pick the highest-confidence object (excluding person).
 * Shows a box whenever something is detected, regardless of position.
 */
function pickBestDetection(predictions, videoW, videoH) {
  const valid = predictions.filter(
    (p) => p.score >= MIN_SCORE && !IGNORED_CLASSES.has(p.class)
  );
  if (valid.length === 0) return null;
  return valid.sort((a, b) => b.score - a.score)[0];
}

function getMotionDiff(ctx, prevData, width, height) {
  const current = ctx.getImageData(0, 0, width, height).data;
  if (!prevData) return { diff: 0, data: current };

  let sum = 0;
  let count = 0;
  for (let y = 0; y < height; y += MOTION_SCAN_STEP) {
    for (let x = 0; x < width; x += MOTION_SCAN_STEP) {
      const i = (y * width + x) * 4;
      sum += Math.abs(current[i] - prevData[i]);
      sum += Math.abs(current[i + 1] - prevData[i + 1]);
      sum += Math.abs(current[i + 2] - prevData[i + 2]);
      count++;
    }
  }
  return { diff: sum / (count * 3), data: current };
}

export default function CameraFeed() {
  const videoRef = useRef(null);
  const canvasRef = useRef(null);
  const modelRef = useRef(null);
  const stateRef = useRef(STATES.LOADING);
  const stableCountRef = useRef(0);
  const missCountRef = useRef(0);
  const lastDetectionRef = useRef(null);
  const detectingRef = useRef(false);
  const scanningLockRef = useRef(false);
  const intervalRef = useRef(null);
  const cityRef = useRef("seattle");
  const smoothBboxRef = useRef(null);

  /** When we entered DETECTED state (for time-based scan trigger). */
  const detectedAtRef = useRef(0);
  const boxClearTimeoutRef = useRef(null);

  const noDetectCountRef = useRef(0);
  const motionPrevFrameRef = useRef(null);
  const motionStableRef = useRef(0);
  const motionActiveRef = useRef(false);

  const [city, setCity, locationStatus] = useClosestCity();
  const [status, setStatus] = useState("Loading object detector...");
  const [result, setResult] = useState(null);
  const [error, setError] = useState(null);
  const [scanning, setScanning] = useState(false);
  const [trackingBox, setTrackingBox] = useState(null);

  useEffect(() => { cityRef.current = city; }, [city]);

  useEffect(() => {
    if (!result) return;
    const t = setTimeout(() => setResult(null), 2500);
    return () => clearTimeout(t);
  }, [result]);

  useEffect(() => {
    if (!error) return;
    const t = setTimeout(() => setError(null), 8000);
    return () => clearTimeout(t);
  }, [error]);

  useEffect(() => {
    let cancelled = false;
    async function loadModel() {
      await tf.ready();
      const model = await cocoSsd.load({ base: "lite_mobilenet_v2" });
      if (!cancelled) {
        modelRef.current = model;
        stateRef.current = STATES.IDLE;
        setStatus("Ready — hold up an item");
      }
    }
    loadModel().catch((err) => {
      if (!cancelled) {
        setStatus("Failed to load detector");
        setError("Could not load object detection model: " + err.message);
      }
    });
    return () => { cancelled = true; };
  }, []);

  const resetDetection = useCallback((clearBox = true) => {
    stableCountRef.current = 0;
    missCountRef.current = 0;
    lastDetectionRef.current = null;
    noDetectCountRef.current = 0;
    motionPrevFrameRef.current = null;
    motionStableRef.current = 0;
    motionActiveRef.current = false;
    if (clearBox) {
      smoothBboxRef.current = null;
      setTrackingBox(null);
    }
  }, []);

  const captureAndScan = useCallback(async () => {
    if (scanningLockRef.current) return;
    scanningLockRef.current = true;

    const video = videoRef.current;
    const canvas = canvasRef.current;
    if (!video || !canvas || video.videoWidth === 0 || video.videoHeight === 0) {
      scanningLockRef.current = false;
      return;
    }

    stateRef.current = STATES.SCANNING;
    setScanning(true);
    setStatus("Checking facility specs...");
    setResult(null);
    setError(null);

    const ctx = canvas.getContext("2d");
    const scale = Math.min(1, CAPTURE_WIDTH / video.videoWidth);
    canvas.width = Math.round(video.videoWidth * scale);
    canvas.height = Math.round(video.videoHeight * scale);
    ctx.drawImage(video, 0, 0, canvas.width, canvas.height);

    try {
      const blob = await new Promise((resolve) => canvas.toBlob(resolve, "image/jpeg", 0.7));

      if (!blob || blob.size === 0) {
        throw new Error("Failed to capture image from camera");
      }

      const form = new FormData();
      form.append("image", blob, "capture.jpg");
      form.append("city", cityRef.current);

      const res = await axios.post(`${API_URL}/scan`, form, {
        timeout: SCAN_TIMEOUT_MS,
      });

      if (!res.data || typeof res.data !== "object") {
        throw new Error("Invalid response from server");
      }

      if (res.data.action === "N/A") {
        stateRef.current = STATES.IDLE;
        resetDetection();
        setScanning(false);
        setStatus("No item found — try again");
        setTimeout(() => {
          if (stateRef.current === STATES.IDLE) {
            setStatus("Ready — hold up an item");
          }
        }, 2000);
        return;
      }

      setResult(res.data);
      setScanning(false);
      stateRef.current = STATES.COOLDOWN;
      setStatus("");
      resetDetection(false);
      setTimeout(() => {
        stateRef.current = STATES.IDLE;
        smoothBboxRef.current = null;
        setTrackingBox(null);
        setStatus("Ready — hold up an item");
      }, COOLDOWN_MS);
    } catch (err) {
      let msg;
      if (err.code === "ECONNABORTED" || err.message?.includes("timeout")) {
        msg = "Scan timed out — the server took too long. Try again.";
      } else if (!err.response) {
        msg = "Cannot reach server. Is the backend running?";
      } else {
        msg = err.response?.data?.error || err.response?.data?.detail || err.message;
      }
      setError(msg);
      setScanning(false);
      stateRef.current = STATES.COOLDOWN;
      resetDetection(false);
      setTimeout(() => {
        stateRef.current = STATES.IDLE;
        smoothBboxRef.current = null;
        setTrackingBox(null);
        setStatus("Ready — hold up an item");
      }, COOLDOWN_MS);
    } finally {
      scanningLockRef.current = false;
    }
  }, [resetDetection]);

  const handleManualScan = useCallback(() => {
    if (
      !scanningLockRef.current &&
      (stateRef.current === STATES.IDLE || stateRef.current === STATES.DETECTED)
    ) {
      captureAndScan();
    }
  }, [captureAndScan]);

  const detectLoop = useCallback(async () => {
    const video = videoRef.current;
    const canvas = canvasRef.current;
    const model = modelRef.current;
    if (!video || !model || !canvas || video.readyState < 2) return;
    if (stateRef.current === STATES.COOLDOWN || stateRef.current === STATES.SCANNING || stateRef.current === STATES.LOADING) return;
    if (detectingRef.current) return;

    detectingRef.current = true;

    try {
      const predictions = await model.detect(video);
      const best = pickBestDetection(predictions, video.videoWidth, video.videoHeight);

      if (best) {
        missCountRef.current = 0;
        noDetectCountRef.current = 0;
        motionPrevFrameRef.current = null;
        motionStableRef.current = 0;
        motionActiveRef.current = false;

        const normalized = normalizeBbox(best.bbox, video.videoWidth, video.videoHeight);

        if (!smoothBboxRef.current) {
          smoothBboxRef.current = { ...normalized };
        } else {
          smoothBboxRef.current = lerpBox(smoothBboxRef.current, normalized, LERP_FACTOR);
        }
        setTrackingBox({ ...smoothBboxRef.current });

        const prev = lastDetectionRef.current;
        if (prev && computeIoU(prev.bbox, normalized) > IOU_THRESHOLD) {
          // Same region — increment stability regardless of class label
          stableCountRef.current += 1;
        } else if (prev) {
          // Different region — don't fully reset, just hold current count
          stableCountRef.current = Math.max(1, stableCountRef.current - 1);
        } else {
          stableCountRef.current = 1;
        }
        lastDetectionRef.current = { class: best.class, bbox: normalized };

        if (stateRef.current === STATES.IDLE) {
          stateRef.current = STATES.DETECTED;
          if (boxClearTimeoutRef.current) {
            clearTimeout(boxClearTimeoutRef.current);
            boxClearTimeoutRef.current = null;
          }
          detectedAtRef.current = Date.now();
          setStatus("Object detected — hold still...");
        }

        const elapsed = Date.now() - detectedAtRef.current;
        const triggerByStability = stateRef.current === STATES.DETECTED && stableCountRef.current >= STABLE_FRAMES_NEEDED;
        const triggerByTime = stateRef.current === STATES.DETECTED && elapsed >= DETECTED_TRIGGER_MS;
        if (triggerByStability || triggerByTime) {
          captureAndScan();
        }
      } else {
        noDetectCountRef.current += 1;

        if (stateRef.current === STATES.DETECTED) {
          missCountRef.current += 1;
          if (missCountRef.current >= MAX_MISS_FRAMES) {
            stateRef.current = STATES.IDLE;
            stableCountRef.current = 0;
            missCountRef.current = 0;
            lastDetectionRef.current = null;
            setStatus("Ready — hold up an item");
            if (boxClearTimeoutRef.current) clearTimeout(boxClearTimeoutRef.current);
            boxClearTimeoutRef.current = setTimeout(() => {
              smoothBboxRef.current = null;
              setTrackingBox(null);
              boxClearTimeoutRef.current = null;
            }, 1500);
          }
        } else {
          smoothBboxRef.current = null;
          setTrackingBox(null);
        }

        // Motion fallback for objects COCO-SSD can't recognize
        if (noDetectCountRef.current >= MOTION_FALLBACK_FRAMES && stateRef.current === STATES.IDLE) {
          const ctx = canvas.getContext("2d");
          canvas.width = video.videoWidth;
          canvas.height = video.videoHeight;
          ctx.drawImage(video, 0, 0);

          const { diff, data } = getMotionDiff(ctx, motionPrevFrameRef.current, canvas.width, canvas.height);
          motionPrevFrameRef.current = data;

          if (diff > MOTION_DIFF_THRESHOLD) {
            motionActiveRef.current = true;
            motionStableRef.current = 0;
            setStatus("Object detected — hold still...");
          } else if (motionActiveRef.current) {
            motionStableRef.current += 1;
            if (motionStableRef.current >= MOTION_STABLE_FRAMES) {
              motionActiveRef.current = false;
              motionStableRef.current = 0;
              captureAndScan();
            }
          }
        }
      }
    } catch {
      // Inference error — skip frame
    } finally {
      detectingRef.current = false;
    }
  }, [captureAndScan]);

  useEffect(() => {
    let stream = null;

    async function startCamera() {
      try {
        stream = await navigator.mediaDevices.getUserMedia({
          video: { facingMode: "environment", width: { ideal: 1280 }, height: { ideal: 720 } },
          audio: false,
        });
        if (videoRef.current) {
          videoRef.current.srcObject = stream;
        }
      } catch {
        setStatus("Camera access denied");
        setError("Could not access camera. Please allow camera permissions.");
      }
    }

    startCamera();
    intervalRef.current = setInterval(detectLoop, DETECT_INTERVAL_MS);

    return () => {
      clearInterval(intervalRef.current);
      if (stream) stream.getTracks().forEach((t) => t.stop());
    };
  }, [detectLoop]);

  const canManualScan = !scanning && stateRef.current !== STATES.LOADING && stateRef.current !== STATES.COOLDOWN;

  return (
    <div className="fixed inset-0 bg-black">
      <video
        ref={videoRef}
        autoPlay
        playsInline
        muted
        className="absolute inset-0 w-full h-full object-cover -scale-x-100"
      />

      <canvas ref={canvasRef} className="hidden" />

      {trackingBox && (
        <div
          className={`absolute pointer-events-none z-[5] ${scanning ? "animate-pulse" : ""}`}
          style={{
            left: `${(1 - trackingBox.x - trackingBox.w) * 100}%`,
            top: `${trackingBox.y * 100}%`,
            width: `${trackingBox.w * 100}%`,
            height: `${trackingBox.h * 100}%`,
          }}
        >
          <div className={`absolute inset-0 rounded-2xl border-2 transition-shadow duration-300 ${
            scanning
              ? "border-emerald-400 shadow-[0_0_24px_rgba(16,185,129,0.6)]"
              : "border-emerald-400/70 shadow-[0_0_12px_rgba(16,185,129,0.25)]"
          }`} />
          <div className="absolute -top-0.5 -left-0.5 w-10 h-10 border-t-[3px] border-l-[3px] border-emerald-300 rounded-tl-2xl" />
          <div className="absolute -top-0.5 -right-0.5 w-10 h-10 border-t-[3px] border-r-[3px] border-emerald-300 rounded-tr-2xl" />
          <div className="absolute -bottom-0.5 -left-0.5 w-10 h-10 border-b-[3px] border-l-[3px] border-emerald-300 rounded-bl-2xl" />
          <div className="absolute -bottom-0.5 -right-0.5 w-10 h-10 border-b-[3px] border-r-[3px] border-emerald-300 rounded-br-2xl" />
        </div>
      )}

      <div className="absolute top-0 left-0 right-0 z-10 bg-black/70 backdrop-blur-sm px-5 py-4 flex items-center justify-between">
        <div>
          <div className="text-white font-extrabold text-2xl tracking-tight">Bin Sentinel</div>
          <div className="text-emerald-300 text-sm mt-0.5">Hold your item up to the camera</div>
        </div>
        <CitySelector value={city} onChange={setCity} locationStatus={locationStatus} />
      </div>

      <div className="absolute bottom-10 left-0 right-0 flex flex-col items-center gap-4 z-10">
        {!result && !error && status && (
          <span className={`px-8 py-4 rounded-full text-xl font-bold backdrop-blur-sm pointer-events-none ${
            scanning ? "bg-emerald-600/80 text-white" : "bg-black/60 text-white/90"
          }`}>
            {status}
          </span>
        )}

        {!result && !error && canManualScan && (
          <button
            onClick={handleManualScan}
            className="px-6 py-3 rounded-full text-base font-semibold bg-white/15 backdrop-blur-sm text-white/80 border border-white/20 active:bg-white/30 transition-colors"
          >
            Scan manually
          </button>
        )}
      </div>

      {result && (
        <ResultOverlay
          item={result.item}
          action={result.action}
          reason={result.reason}
          confidence={result.confidence}
          city={result.city}
          onDismiss={() => setResult(null)}
        />
      )}

      {error && (
        <div
          className="absolute bottom-0 left-0 right-0 z-20 bg-red-900/90 backdrop-blur-md text-white px-8 py-8 rounded-t-3xl cursor-pointer"
          onClick={() => setError(null)}
        >
          <div className="w-12 h-1.5 bg-white/30 rounded-full mx-auto mb-5" />
          <div className="font-bold text-2xl mb-3">Error</div>
          <div className="text-lg leading-relaxed">{error}</div>
        </div>
      )}
    </div>
  );
}
