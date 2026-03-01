import { useRef, useState, useEffect, useCallback } from "react";
import axios from "axios";
import CitySelector from "./CitySelector";
import { ResultOverlay } from "./ResultCard";
import { useClosestCity } from "./hooks/useClosestCity";

const API_URL = import.meta.env.VITE_API_URL || "http://localhost:8000";

const STATES = { IDLE: "IDLE", CHANGE_DETECTED: "CHANGE_DETECTED", COOLDOWN: "COOLDOWN", SCANNING: "SCANNING" };
const DIFF_THRESHOLD_HIGH = 15;
const DIFF_THRESHOLD_LOW = 8;
const STABLE_FRAMES_NEEDED = 1;
const COOLDOWN_MS = 5000;
const FRAME_INTERVAL_MS = 250;
const CAPTURE_WIDTH = 640;

function getMeanDiff(ctx, prevData, width, height) {
  const cx = Math.floor(width * 0.3);
  const cy = Math.floor(height * 0.3);
  const cw = Math.floor(width * 0.4);
  const ch = Math.floor(height * 0.4);
  const current = ctx.getImageData(cx, cy, cw, ch).data;

  if (!prevData) return { diff: 0, data: current };

  let sum = 0;
  const len = current.length;
  for (let i = 0; i < len; i += 4) {
    sum += Math.abs(current[i] - prevData[i]);
    sum += Math.abs(current[i + 1] - prevData[i + 1]);
    sum += Math.abs(current[i + 2] - prevData[i + 2]);
  }
  const pixels = len / 4;
  return { diff: sum / (pixels * 3), data: current };
}

export default function CameraFeed() {
  const videoRef = useRef(null);
  const canvasRef = useRef(null);
  const prevFrameRef = useRef(null);
  const stateRef = useRef(STATES.IDLE);
  const stableCountRef = useRef(0);
  const intervalRef = useRef(null);
  const cityRef = useRef("seattle");

  const [city, setCity, locationStatus] = useClosestCity();
  const [status, setStatus] = useState("Starting camera...");
  const [result, setResult] = useState(null);
  const [error, setError] = useState(null);
  const [scanning, setScanning] = useState(false);

  // Keep cityRef in sync
  useEffect(() => { cityRef.current = city; }, [city]);

  // Auto-dismiss result after 6s
  useEffect(() => {
    if (!result) return;
    const t = setTimeout(() => setResult(null), 6000);
    return () => clearTimeout(t);
  }, [result]);

  // Auto-dismiss error after 4s
  useEffect(() => {
    if (!error) return;
    const t = setTimeout(() => setError(null), 4000);
    return () => clearTimeout(t);
  }, [error]);

  const captureAndScan = useCallback(async () => {
    const video = videoRef.current;
    const canvas = canvasRef.current;
    if (!video || !canvas) return;

    stateRef.current = STATES.SCANNING;
    setScanning(true);
    setStatus("Checking facility specs...");
    setResult(null);
    setError(null);

    const ctx = canvas.getContext("2d");
    // Downscale for faster upload
    const scale = Math.min(1, CAPTURE_WIDTH / video.videoWidth);
    canvas.width = Math.round(video.videoWidth * scale);
    canvas.height = Math.round(video.videoHeight * scale);
    ctx.drawImage(video, 0, 0, canvas.width, canvas.height);

    try {
      const blob = await new Promise((resolve) => canvas.toBlob(resolve, "image/jpeg", 0.6));
      const form = new FormData();
      form.append("image", blob, "capture.jpg");
      form.append("city", cityRef.current);

      const res = await axios.post(`${API_URL}/scan`, form);
      if (res.data.action === "N/A") {
        // No item detected — skip cooldown, resume detection immediately
        setScanning(false);
        prevFrameRef.current = null;
        stableCountRef.current = 0;
        stateRef.current = STATES.IDLE;
        setStatus("Ready — hold up an item");
        return;
      }
      setResult(res.data);
    } catch (err) {
      const msg = err.response?.data?.error || err.response?.data?.detail || err.message;
      setError(msg);
    } finally {
      if (stateRef.current === STATES.SCANNING) {
        setScanning(false);
        // Enter cooldown only for real scans
        stateRef.current = STATES.COOLDOWN;
        setStatus("Cooldown...");
        prevFrameRef.current = null;
        stableCountRef.current = 0;
        setTimeout(() => {
          stateRef.current = STATES.IDLE;
          setStatus("Ready — hold up an item");
        }, COOLDOWN_MS);
      }
    }
  }, []);

  const detectLoop = useCallback(() => {
    const video = videoRef.current;
    const canvas = canvasRef.current;
    if (!video || !canvas || video.readyState < 2) return;

    if (stateRef.current === STATES.COOLDOWN || stateRef.current === STATES.SCANNING) return;

    const ctx = canvas.getContext("2d");
    canvas.width = video.videoWidth;
    canvas.height = video.videoHeight;
    ctx.drawImage(video, 0, 0);

    const { diff, data } = getMeanDiff(ctx, prevFrameRef.current, canvas.width, canvas.height);
    prevFrameRef.current = data;

    if (stateRef.current === STATES.IDLE) {
      if (diff > DIFF_THRESHOLD_HIGH) {
        stateRef.current = STATES.CHANGE_DETECTED;
        stableCountRef.current = 0;
        setStatus("Object detected — hold still...");
      }
    } else if (stateRef.current === STATES.CHANGE_DETECTED) {
      if (diff < DIFF_THRESHOLD_LOW) {
        stableCountRef.current += 1;
        if (stableCountRef.current >= STABLE_FRAMES_NEEDED) {
          captureAndScan();
        }
      } else if (diff > DIFF_THRESHOLD_HIGH) {
        // Still moving, reset stable count
        stableCountRef.current = 0;
      } else {
        // Moderate movement — keep waiting but don't reset
      }
    }
  }, [captureAndScan]);

  // Start camera and detection loop
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
          setStatus("Ready — hold up an item");
        }
      } catch (err) {
        setStatus("Camera access denied");
        setError("Could not access camera. Please allow camera permissions.");
      }
    }

    startCamera();
    intervalRef.current = setInterval(detectLoop, FRAME_INTERVAL_MS);

    return () => {
      clearInterval(intervalRef.current);
      if (stream) stream.getTracks().forEach((t) => t.stop());
    };
  }, [detectLoop]);

  return (
    <div className="fixed inset-0 bg-black">
      {/* Full-screen video */}
      <video
        ref={videoRef}
        autoPlay
        playsInline
        muted
        className="absolute inset-0 w-full h-full object-cover -scale-x-100"
      />

      {/* Hidden canvas for frame capture */}
      <canvas ref={canvasRef} className="hidden" />

      {/* Translucent green overlay with cutout */}
      <div className="absolute inset-0 pointer-events-none" style={{
        background: `
          linear-gradient(to bottom,
            rgba(16,185,129,0.45) 0%,
            rgba(16,185,129,0.45) 15%,
            transparent 15%,
            transparent 85%,
            rgba(16,185,129,0.45) 85%,
            rgba(16,185,129,0.45) 100%
          )
        `,
      }} />
      <div className="absolute inset-0 pointer-events-none" style={{
        background: `
          linear-gradient(to right,
            rgba(16,185,129,0.45) 0%,
            rgba(16,185,129,0.45) 10%,
            transparent 10%,
            transparent 90%,
            rgba(16,185,129,0.45) 90%,
            rgba(16,185,129,0.45) 100%
          )
        `,
        clipPath: 'polygon(0 15%, 100% 15%, 100% 85%, 0 85%)',
      }} />

      {/* Scanning box border */}
      <div className="absolute pointer-events-none border-2 border-emerald-400/60 rounded-2xl"
        style={{ top: '15%', bottom: '15%', left: '10%', right: '10%' }}
      >
        {/* Corner accents */}
        <div className="absolute top-0 left-0 w-8 h-8 border-t-4 border-l-4 border-emerald-400 rounded-tl-2xl" />
        <div className="absolute top-0 right-0 w-8 h-8 border-t-4 border-r-4 border-emerald-400 rounded-tr-2xl" />
        <div className="absolute bottom-0 left-0 w-8 h-8 border-b-4 border-l-4 border-emerald-400 rounded-bl-2xl" />
        <div className="absolute bottom-0 right-0 w-8 h-8 border-b-4 border-r-4 border-emerald-400 rounded-br-2xl" />
      </div>

      {/* Top bar: Branding + welcome message + city selector */}
      <div className="absolute top-0 left-0 right-0 z-10 bg-black/70 backdrop-blur-sm px-4 py-3 flex items-center justify-between">
        <div>
          <div className="text-white font-bold text-lg">Bin Sentinel</div>
          <div className="text-emerald-300 text-xs">Welcome — please hold your item up to the camera</div>
        </div>
        <CitySelector value={city} onChange={setCity} locationStatus={locationStatus} />
      </div>

      {/* Bottom: Status text */}
      <div className="absolute bottom-6 left-0 right-0 flex justify-center z-10 pointer-events-none">
        {!result && !error && (
          <span className={`px-4 py-2 rounded-full text-sm font-medium backdrop-blur-sm ${
            scanning ? "bg-emerald-600/80 text-white" : "bg-black/60 text-white/90"
          }`}>
            {status}
          </span>
        )}
      </div>

      {/* Result overlay */}
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

      {/* Error overlay */}
      {error && (
        <div
          className="absolute bottom-6 left-4 right-4 z-20 bg-red-900/80 backdrop-blur-sm text-white p-4 rounded-xl cursor-pointer"
          onClick={() => setError(null)}
        >
          <div className="font-semibold mb-1">Error</div>
          <div className="text-sm">{error}</div>
        </div>
      )}
    </div>
  );
}
