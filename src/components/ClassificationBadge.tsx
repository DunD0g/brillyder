import React from 'react';
import { CLASSIFICATION_META, type MoveClassification } from '../types/chess';
import { getClassificationLabel, useVibe } from '../utils/vibeCopy';

interface Props {
  classification: MoveClassification;
  size?: 'xs' | 'sm' | 'md';
  showLabel?: boolean;
}

export const ClassificationBadge: React.FC<Props> = ({ classification, size = 'sm', showLabel = false }) => {
  const { vibe } = useVibe();
  const m = CLASSIFICATION_META[classification];
  const label = getClassificationLabel(classification, vibe);
  const sz = size === 'xs' ? 'h-4 min-w-[16px] px-1 text-[10px]' : size === 'md' ? 'h-7 min-w-[28px] px-2 text-xs' : 'h-5 min-w-[20px] px-1.5 text-[11px]';
  return (
    <span className={`inline-flex items-center gap-1 rounded-full font-bold border ${m.bgClass} ${m.textClass} ${m.borderClass} ${sz}`} title={label}>
      <span>{m.symbol}</span>
      {showLabel && <span className="font-semibold">{label}</span>}
    </span>
  );
};
