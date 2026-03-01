const CITIES = [
  { value: "seattle", label: "Seattle" },
  { value: "nyc", label: "NYC" },
  { value: "la", label: "Los Angeles" },
  { value: "chicago", label: "Chicago" },
];

export default function CitySelector({ value, onChange, locationStatus }) {
  return (
    <div className="flex flex-col items-end gap-0.5">
      {locationStatus === "detecting" && (
        <span className="text-emerald-300/90 text-xs">Detecting location...</span>
      )}
      {locationStatus === "detected" && (
        <span className="text-emerald-300/90 text-xs">Using your location</span>
      )}
      {locationStatus === "denied" && (
        <span className="text-amber-400/90 text-xs">Location denied — choose city</span>
      )}
      {locationStatus === "unavailable" && (
        <span className="text-white/60 text-xs">Location unavailable</span>
      )}
      <select
        value={value}
        onChange={(e) => onChange(e.target.value)}
        className="bg-black/60 backdrop-blur-sm text-white border border-white/30 rounded-full px-3 py-1.5 text-sm focus:border-white/60 focus:outline-none appearance-none cursor-pointer"
      >
        {CITIES.map((c) => (
          <option key={c.value} value={c.value}>
            {c.label}
          </option>
        ))}
      </select>
    </div>
  );
}
