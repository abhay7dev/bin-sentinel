import { useRef, useState } from "react";
import axios from "axios";
import CitySelector from "./CitySelector";
import ResultCard from "./ResultCard";

const API_URL = import.meta.env.VITE_API_URL || "http://localhost:8000";

export default function Scanner({ onScanComplete }) {
  const fileInputRef = useRef(null);
  const [city, setCity] = useState("seattle");
  const [loading, setLoading] = useState(false);
  const [result, setResult] = useState(null);
  const [error, setError] = useState(null);

  const handleFileChange = async (e) => {
    const file = e.target.files[0];
    if (!file) return;

    setLoading(true);
    setResult(null);
    setError(null);

    const form = new FormData();
    form.append("image", file);
    form.append("city", city);

    try {
      const res = await axios.post(`${API_URL}/scan`, form);
      setResult(res.data);
      if (onScanComplete) onScanComplete();
    } catch (err) {
      const msg =
        err.response?.data?.error ||
        err.response?.data?.detail ||
        err.message;
      setError(msg);
    } finally {
      setLoading(false);
      fileInputRef.current.value = "";
    }
  };

  return (
    <div>
      <div className="flex items-center gap-3 mb-4">
        <CitySelector value={city} onChange={setCity} />
        <button
          onClick={() => fileInputRef.current.click()}
          disabled={loading}
          className="bg-blue-600 text-white px-4 py-2 rounded hover:bg-blue-700 disabled:opacity-50"
        >
          {loading ? "Checking facility specs..." : "Scan Item"}
        </button>
      </div>

      <input
        ref={fileInputRef}
        type="file"
        accept="image/*"
        capture="environment"
        onChange={handleFileChange}
        className="hidden"
      />

      {loading && (
        <div className="text-gray-500 mt-2">Checking facility specs...</div>
      )}

      {error && <div className="text-red-600 mt-2">{error}</div>}

      {result && <ResultCard {...result} />}
    </div>
  );
}
