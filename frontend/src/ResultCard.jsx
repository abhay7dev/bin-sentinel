const ACTION_STYLES = {
  RECYCLE: "bg-green-100 border-green-500 text-green-800",
  TRASH: "bg-red-100 border-red-500 text-red-800",
  COMPOST: "bg-amber-100 border-amber-500 text-amber-800",
};

export default function ResultCard({ item, action, reason, confidence, city }) {
  const style = ACTION_STYLES[action] || ACTION_STYLES.TRASH;

  return (
    <div className={`border-2 rounded-lg p-4 mt-4 ${style}`}>
      <div className="text-2xl font-bold mb-2">{action}</div>
      <div className="text-lg font-medium mb-1">{item}</div>
      <div className="mb-1">{reason}</div>
      <div className="text-sm opacity-75">
        Confidence: {confidence} &middot; City: {city}
      </div>
    </div>
  );
}
