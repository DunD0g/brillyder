import React, { useRef, useState } from 'react';
import { Clock } from 'lucide-react';
import { CLASSIFICATION_META, type AnalyzedPly, type EngineScore } from '../types/chess';

interface Props {
  initialEval: EngineScore;
  plies: AnalyzedPly[];
  currentPlyIndex: number;
  onSelectPly: (idx: number) => void;
}

export const EvalGraph: React.FC<Props> = ({ initialEval, plies, currentPlyIndex, onSelectPly }) => {
  const svgRef = useRef<SVGSVGElement | null>(null);
  const [showClockOverlay, setShowClockOverlay] = useState(false);

  const width = 360;
  const height = 84;
  const hasClockSpent = plies.some((p) => p.timeSpentSeconds !== undefined && p.timeSpentSeconds > 0);
  const maxSpent = Math.max(15, ...plies.map((p) => Math.min(90, p.timeSpentSeconds ?? 0)));

  const pts = [
    {
      wp: initialEval.winPercentWhite,
      cls: null as AnalyzedPly['classification'] | null,
      spent: 0,
      clockTag: undefined as AnalyzedPly['clockTag'],
    },
    ...plies.map((p) => ({
      wp: p.evalAfter.winPercentWhite,
      cls: p.classification,
      spent: Math.min(90, p.timeSpentSeconds ?? 0),
      clockTag: p.clockTag,
    })),
  ];

  const xFor = (i: number) => (pts.length <= 1 ? 0 : (i / (pts.length - 1)) * width);
  const yFor = (wp: number) => height - (Math.max(0, Math.min(100, wp)) / 100) * height;
  const line = pts.map((p, i) => `${i === 0 ? 'M' : 'L'} ${xFor(i).toFixed(1)} ${yFor(p.wp).toFixed(1)}`).join(' ');
  const area = `${line} L ${width} ${height} L 0 ${height} Z`;
  const activeIdx = Math.min(currentPlyIndex, pts.length - 1);

  const handleTap = (clientX: number) => {
    if (!svgRef.current || pts.length <= 1) return;
    const r = svgRef.current.getBoundingClientRect();
    const ratio = Math.max(0, Math.min(1, (clientX - r.left) / r.width));
    onSelectPly(Math.round(ratio * (pts.length - 1)));
  };

  return (
    <div className="rounded-xl border border-slate-800 bg-slate-900/90 p-2">
      <div className="mb-1 flex items-center justify-between gap-2 px-1 text-[11px] text-slate-400">
        <span className="font-semibold text-slate-300">
          {showClockOverlay ? 'Time Spent vs. Eval Swing' : 'Evaluation Advantage'}
        </span>
        <div className="flex items-center gap-2">
          {hasClockSpent && (
            <button
              type="button"
              onClick={() => setShowClockOverlay((v) => !v)}
              className={`inline-flex items-center gap-1 rounded-md border px-1.5 py-0.5 text-[9px] font-bold transition ${
                showClockOverlay
                  ? 'border-purple-400/50 bg-purple-500/20 text-purple-200'
                  : 'border-slate-700 bg-slate-950/60 text-slate-400 hover:text-slate-200'
              }`}
            >
              <Clock className="h-2.5 w-2.5" /> Clock overlay
            </button>
          )}
          <span className="text-[10px]">Tap to jump</span>
        </div>
      </div>

      <svg
        ref={svgRef}
        viewBox={`0 0 ${width} ${height}`}
        className="h-20 w-full cursor-pointer select-none rounded-lg bg-slate-950 touch-pan-y"
        onClick={(e) => handleTap(e.clientX)}
      >
        <rect x="0" y="0" width={width} height={height / 2} fill="#0F172A" />
        <rect x="0" y={height / 2} width={width} height={height / 2} fill="#070B14" />
        <line x1="0" y1={height / 2} x2={width} y2={height / 2} stroke="#334155" strokeDasharray="3 3" />

        {showClockOverlay &&
          pts.map((pt, i) => {
            if (i === 0 || pt.spent <= 0) return null;
            const barH = Math.max(3, (pt.spent / maxSpent) * (height - 8));
            const barW = Math.max(2, width / Math.max(12, pts.length) - 0.8);
            const fill =
              pt.clockTag === 'impulse'
                ? 'rgba(251, 191, 36, 0.72)'
                : pt.clockTag === 'time-trouble'
                  ? 'rgba(251, 113, 133, 0.72)'
                  : 'rgba(168, 85, 247, 0.36)';
            return (
              <rect
                key={`clk-${i}`}
                x={xFor(i) - barW / 2}
                y={height - barH}
                width={barW}
                height={barH}
                rx={1}
                fill={fill}
              />
            );
          })}

        {!showClockOverlay && <path d={area} fill="rgba(241, 245, 249, 0.85)" />}
        <path d={line} fill="none" stroke="#2DD4BF" strokeWidth="1.9" />

        {pts.map((pt, i) =>
          pt.cls && (pt.cls === 'blunder' || pt.cls === 'mistake' || pt.cls === 'brilliant' || pt.cls === 'great') ? (
            <circle
              key={i}
              cx={xFor(i)}
              cy={yFor(pt.wp)}
              r={pt.cls === 'blunder' || pt.cls === 'brilliant' ? 3.5 : 2.6}
              fill={
                pt.clockTag === 'impulse'
                  ? '#FBBF24'
                  : CLASSIFICATION_META[pt.cls].badgeBg
              }
              stroke="#070B14"
              strokeWidth="1"
            />
          ) : null
        )}
        <line x1={xFor(activeIdx)} y1="0" x2={xFor(activeIdx)} y2={height} stroke="#2DD4BF" strokeWidth="1.5" />
        <circle cx={xFor(activeIdx)} cy={yFor(pts[activeIdx]?.wp ?? 50)} r="4" fill="#2DD4BF" stroke="#070B14" strokeWidth="1.5" />
      </svg>

      {showClockOverlay && (
        <div className="mt-1 flex flex-wrap items-center gap-3 px-1 text-[9px] text-slate-400">
          <span className="inline-flex items-center gap-1">
            <span className="h-2 w-2 rounded-sm bg-purple-400/70" /> Time spent
          </span>
          <span className="inline-flex items-center gap-1">
            <span className="h-2 w-2 rounded-sm bg-amber-400" /> Impulse (&lt;5s, &gt;3m)
          </span>
          <span className="inline-flex items-center gap-1">
            <span className="h-2 w-2 rounded-sm bg-rose-400" /> Time trouble (&lt;60s)
          </span>
        </div>
      )}
    </div>
  );
};
