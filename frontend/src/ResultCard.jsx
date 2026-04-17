const ACTION_STYLES = {
  RECYCLE: "bg-blue-900/50 border-blue-500 text-blue-300",
  TRASH: "bg-red-900/50 border-red-500 text-red-300",
  COMPOST: "bg-green-900/50 border-green-500 text-green-300",
  SPECIAL: "bg-purple-900/50 border-purple-500 text-purple-300",
};

const ACTION_LABELS = {
  SPECIAL: "SPECIAL DISPOSAL",
};

const ACTION_ICONS = {
  RECYCLE: (
    <svg className="w-12 h-12 flex-shrink-0" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      <path d="M7 2v4M17 2v4M2 12h4M18 12h4M4.93 4.93l2.83 2.83M16.24 16.24l2.83 2.83M4.93 19.07l2.83-2.83M16.24 7.76l2.83-2.83" />
      <path d="M12 6a6 6 0 1 1 0 12 6 6 0 0 1 0-12z" />
    </svg>
  ),
  TRASH: (
    <svg className="w-12 h-12 flex-shrink-0" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      <polyline points="3 6 5 6 21 6" />
      <path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2" />
      <line x1="10" y1="11" x2="10" y2="17" />
      <line x1="14" y1="11" x2="14" y2="17" />
    </svg>
  ),
  COMPOST: (
    <svg className="w-12 h-12 flex-shrink-0" viewBox="0 0 24 24" fill="currentColor" aria-hidden>
      <path d="M17 8C8 10 5.9 16.17 3.82 21.34l1.89.66.95-2.3c.48.17.98.3 1.34.3C19 20 22 3 22 3c-1 2-8 2.25-13 3.25S2 11.5 2 13.5s1.75 3.75 1.75 3.75C7 8 17 8 17 8z" />
    </svg>
  ),
  SPECIAL: (
    <svg className="w-12 h-12 flex-shrink-0" viewBox="0 0 24 24" fill="currentColor" aria-hidden>
      <path d="M12 2l2.4 7.4h7.6l-6 4.6 2.3 7-6.3-4.6-6.3 4.6 2.3-7-6-4.6h7.6L12 2z" />
    </svg>
  ),
};

export default function ResultCard({ item, action, reason, confidence, city }) {
  const style = ACTION_STYLES[action] || ACTION_STYLES.TRASH;
  const Icon = ACTION_ICONS[action] || ACTION_ICONS.TRASH;

  return (
    <div className={`border-2 rounded-lg p-4 mt-4 ${style}`}>
      <div className="flex items-center gap-3 mb-2">
        {Icon}
        <div className="text-2xl font-bold">{ACTION_LABELS[action] || action}</div>
      </div>
      <div className="mb-1">{reason}</div>
      <div className="text-sm opacity-75">
        Confidence: {confidence} &middot; City: {city}
      </div>
    </div>
  );
}

const OVERLAY_STYLES = {
  RECYCLE: "bg-blue-900/85 border-blue-400",
  TRASH: "bg-red-900/85 border-red-400",
  COMPOST: "bg-green-900/85 border-green-400",
  SPECIAL: "bg-purple-900/85 border-purple-400",
};

export function ResultOverlay({ item, action, reason, confidence, city, onDismiss }) {
  const style = OVERLAY_STYLES[action] || OVERLAY_STYLES.TRASH;
  const Icon = ACTION_ICONS[action] || ACTION_ICONS.TRASH;

  return (
    <div
      className={`absolute bottom-0 left-0 right-0 z-20 border-t-2 rounded-t-3xl px-8 pt-6 pb-10 backdrop-blur-md text-white cursor-pointer ${style}`}
      onClick={onDismiss}
    >
      <div className="w-12 h-1.5 bg-white/30 rounded-full mx-auto mb-6" />
      <div className="flex items-center gap-4 mb-4">
        {Icon}
        <div className="flex-1 min-w-0">
          <div className="flex items-baseline justify-between gap-2 flex-wrap">
            <span className="text-6xl font-black tracking-tight">{ACTION_LABELS[action] || action}</span>
            <span className="text-base opacity-60 uppercase font-semibold">{confidence}</span>
          </div>
        </div>
      </div>
      {item && <div className="text-2xl font-semibold opacity-85 mb-3">{item}</div>}
      <div className="text-xl leading-relaxed">{reason}</div>
      <div className="text-sm opacity-45 mt-4">Based on {city} facility specs &middot; local rules apply</div>
      <div className="text-base opacity-50 mt-2">tap to dismiss</div>
    </div>
  );
}
