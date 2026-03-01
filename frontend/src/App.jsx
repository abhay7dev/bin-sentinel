import { useState } from "react";
import Scanner from "./Scanner";
import History from "./History";

export default function App() {
  const [refreshKey, setRefreshKey] = useState(0);

  return (
    <div className="max-w-lg mx-auto p-4">
      <h1 className="text-2xl font-bold mb-4">Bin Sentinel</h1>
      <Scanner onScanComplete={() => setRefreshKey((k) => k + 1)} />
      <History refreshKey={refreshKey} />
    </div>
  );
}
