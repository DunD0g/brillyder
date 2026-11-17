import React, { useRef } from 'react';
import { CLASSIFICATION_META, type AnalyzedPly, type EngineScore } from '../types/chess';

interface Props {
  initialEval: EngineScore;
  plies: AnalyzedPly[];
  currentPlyIndex: number;
  onSelectPly: (idx: number) => void;
}

export const EvalGraph: React.FC<Props> = ({ initialEval, plies, currentPlyIndex, onSelectPly }) => {
  const svgRef = useRef<SVGSVGElement | null>(null);
  const width = 360;
  const height = 80;
  const pts = [
    { wp: initialEval.winPercentWhite, cls: null as AnalyzedPly['classification'] | null },
    ...plies.map((p) => ({ wp: p.evalAfter.winPercentWhite, cls: p.classification })),
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
    <div className="rounded-xl bg-slate-900/90 border border-slate-800 p-2">
      <div className="flex items-center justify-between text-[11px] text-slate-400 mb-1 px-1">
        <span className="font-semibold text-slate-300">Evaluation Advantage</span>
        <span>Tap graph to jump</span>
      </div>
      <svg
        ref={svgRef}
        viewBox={`0 0 ${width} ${height}`}
        className="w-full h-20 rounded-lg bg-slate-950 cursor-pointer touch-pan-y select-none"
        onClick={(e) => handleTap(e.clientX)}
      >
        <rect x="0" y="0" width={width} height={height / 2} fill="#0f172a" />
        <rect x="0" y={height / 2} width={width} height={height / 2} fill="#090d16" />
        <line x1="0" y1={height / 2} x2={width} y2={height / 2} stroke="#334155" strokeDasharray="3 3" />
        <path d={area} fill="rgba(241, 245, 249, 0.85)" />
        <path d={line} fill="none" stroke="#22d3ee" strokeWidth="1.8" />
        {pts.map((pt, i) =>
          pt.cls && (pt.cls === 'blunder' || pt.cls === 'mistake' || pt.cls === 'brilliant' || pt.cls === 'great') ? (
            <circle
              key={i}
              cx={xFor(i)}
              cy={yFor(pt.wp)}
              r={pt.cls === 'blunder' || pt.cls === 'brilliant' ? 3.5 : 2.6}
              fill={CLASSIFICATION_META[pt.cls].badgeBg}
              stroke="#0b0f19"
              strokeWidth="1"
            />
          ) : null
        )}
        <line x1={xFor(activeIdx)} y1="0" x2={xFor(activeIdx)} y2={height} stroke="#22d3ee" strokeWidth="1.5" />
        <circle cx={xFor(activeIdx)} cy={yFor(pts[activeIdx]?.wp ?? 50)} r="4" fill="#22d3ee" stroke="#0b0f19" strokeWidth="1.5" />
      </svg>
    </div>
  );
};
