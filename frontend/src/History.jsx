import { useEffect, useState } from "react";
import axios from "axios";

const API_URL = import.meta.env.VITE_API_URL || "http://localhost:8000";

const ACTION_COLORS = {
  RECYCLE: "text-green-600",
  TRASH: "text-red-600",
  COMPOST: "text-amber-600",
};

export default function History({ refreshKey }) {
  const [scans, setScans] = useState([]);

  useEffect(() => {
    axios
      .get(`${API_URL}/history`)
      .then((res) => setScans(res.data.scans))
      .catch(() => {});
  }, [refreshKey]);

  if (scans.length === 0) return null;

  return (
    <div className="mt-8">
      <h2 className="text-xl font-bold mb-3">Recent Scans</h2>
      <ul className="space-y-2">
        {scans.map((s, i) => (
          <li key={i} className="border rounded p-2 flex items-center gap-3">
            <span className={`font-bold ${ACTION_COLORS[s.action] || ""}`}>
              {s.action}
            </span>
            <span>{s.item}</span>
            <span className="text-gray-400 text-sm">{s.city}</span>
            <span className="text-gray-400 text-sm ml-auto">
              {new Date(s.timestamp).toLocaleTimeString()}
            </span>
          </li>
        ))}
      </ul>
    </div>
  );
}
