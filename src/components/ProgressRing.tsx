import React, { useEffect, useId, useState } from 'react';

interface Props {
  value: number;
  size?: number;
  stroke?: number;
  label?: string;
  sublabel?: string;
  tone?: 'cyan' | 'emerald' | 'amber' | 'rose';
  className?: string;
}

const TONES: Record<NonNullable<Props['tone']>, { from: string; to: string; text: string }> = {
  cyan: { from: '#22d3ee', to: '#2dd4bf', text: 'text-cyan-200' },
  emerald: { from: '#34d399', to: '#a3e635', text: 'text-emerald-200' },
  amber: { from: '#fbbf24', to: '#fb923c', text: 'text-amber-200' },
  rose: { from: '#fb7185', to: '#f43f5e', text: 'text-rose-200' },
};

export const ProgressRing: React.FC<Props> = ({ value, size = 84, stroke = 7, label, sublabel, tone = 'cyan', className = '' }) => {
  const id = useId().replace(/:/g, '');
  const [shown, setShown] = useState(0);
  const safe = Math.max(0, Math.min(100, value));
  const radius = (size - stroke) / 2;
  const circumference = 2 * Math.PI * radius;
  const offset = circumference * (1 - shown / 100);
  const colors = TONES[tone];

  useEffect(() => {
    const frame = requestAnimationFrame(() => setShown(safe));
    return () => cancelAnimationFrame(frame);
  }, [safe]);

  return (
    <div className={`relative inline-flex items-center justify-center ${className}`} style={{ width: size, height: size }}>
      <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} className="accuracy-ring -rotate-90">
        <defs>
          <linearGradient id={`ring-${id}`} x1="0%" y1="0%" x2="100%" y2="100%">
            <stop offset="0%" stopColor={colors.from} />
            <stop offset="100%" stopColor={colors.to} />
          </linearGradient>
        </defs>
        <circle cx={size / 2} cy={size / 2} r={radius} fill="none" stroke="rgba(148,163,184,0.16)" strokeWidth={stroke} />
        <circle
          cx={size / 2}
          cy={size / 2}
          r={radius}
          fill="none"
          stroke={`url(#ring-${id})`}
          strokeWidth={stroke}
          strokeLinecap="round"
          strokeDasharray={circumference}
          strokeDashoffset={offset}
        />
      </svg>
      <div className="absolute inset-0 flex flex-col items-center justify-center leading-none">
        <span className={`font-extrabold tabular-nums ${colors.text}`} style={{ fontSize: size * 0.24 }}>
          {label ?? `${Math.round(safe)}%`}
        </span>
        {sublabel && <span className="mt-1 text-[8px] font-bold uppercase tracking-wider text-slate-400">{sublabel}</span>}
      </div>
    </div>
  );
};
