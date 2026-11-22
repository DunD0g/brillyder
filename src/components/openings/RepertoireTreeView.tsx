import React, { useMemo, useState } from 'react';
import { GitBranch, Orbit, Play } from 'lucide-react';
import type { BoardThemeId } from '../../types/chess';
import type { FsrsOpeningCard, OpeningCourse } from '../../types/openings';
import { buildRepertoireTree, type RepertoireTreeNode } from '../../services/repertoireTree';
import { ChessgroundBoard } from '../ChessgroundBoard';

interface Props {
  course: OpeningCourse;
  cards: FsrsOpeningCard[];
  boardTheme: BoardThemeId;
  onOpenLineWalkthrough: (lineId: string) => void;
  onDrillLine: (lineId: string) => void;
}

function signalDotClass(node: RepertoireTreeNode): string {
  if (!node.isUserMove) return 'bg-slate-600';
  if (node.dueCount > 0) return 'bg-purple-400';
  if (node.recallPct === null) return 'bg-slate-500';
  if (node.recallPct >= 85) return 'bg-emerald-400';
  if (node.recallPct >= 60) return 'bg-teal-400';
  return 'bg-amber-400';
}

function formatMoveChip(node: RepertoireTreeNode): string {
  const moveNum = Math.floor((node.ply - 1) / 2) + 1;
  const isWhite = (node.ply - 1) % 2 === 0;
  return isWhite ? `${moveNum}.${node.san}` : `${moveNum}…${node.san}`;
}

const TreeBranchRow: React.FC<{
  node: RepertoireTreeNode;
  depth: number;
  selectedId: string;
  onSelect: (node: RepertoireTreeNode) => void;
}> = ({ node, depth, selectedId, onSelect }) => {
  // Collapse single-child main chains horizontally so deep lines stay super readable on mobile
  const chain: RepertoireTreeNode[] = [node];
  let tail = node;
  while (tail.children.length === 1) {
    tail = tail.children[0];
    chain.push(tail);
  }

  return (
    <div className={depth > 0 ? 'ml-3 border-l border-slate-800/90 pl-2.5' : ''}>
      <div className="flex flex-wrap items-center gap-1 py-1">
        {chain.map((step) => {
          const isSelected = step.id === selectedId;
          return (
            <button
              key={step.id}
              type="button"
              onClick={() => onSelect(step)}
              title={
                step.isUserMove
                  ? `${formatMoveChip(step)} · ${step.recallPct !== null ? `Recall ${step.recallPct}%` : 'Locked / New'}${step.dueCount > 0 ? ` · ${step.dueCount} due` : ''}`
                  : `${formatMoveChip(step)} (Opponent)`
              }
              className={`inline-flex items-center gap-1 rounded-lg border px-1.5 py-0.5 font-mono text-[10px] font-bold transition ${
                isSelected
                  ? 'border-teal-400/70 bg-teal-400/20 text-teal-100'
                  : step.isUserMove
                  ? 'border-slate-700/80 bg-hull/90 text-slate-100 hover:border-teal-400/40'
                  : 'border-slate-800/80 bg-void/60 text-slate-400 hover:border-slate-600 hover:text-slate-200'
              }`}
            >
              <span className={`h-1.5 w-1.5 rounded-full ${signalDotClass(step)}`} />
              <span>{formatMoveChip(step)}</span>
            </button>
          );
        })}
      </div>

      {tail.children.length > 1 && (
        <div className="space-y-0.5">
          {tail.children.map((branch) => (
            <TreeBranchRow
              key={branch.id}
              node={branch}
              depth={depth + 1}
              selectedId={selectedId}
              onSelect={onSelect}
            />
          ))}
        </div>
      )}
    </div>
  );
};

export const RepertoireTreeView: React.FC<Props> = ({
  course,
  cards,
  boardTheme,
  onOpenLineWalkthrough,
  onDrillLine,
}) => {
  const tree = useMemo(() => buildRepertoireTree(course, cards), [course, cards]);
  const [selectedNode, setSelectedNode] = useState<RepertoireTreeNode>(
    () => tree.children[0] ?? tree
  );

  // Sync if user switches course
  const activeNode = useMemo(() => {
    if (selectedNode.id === 'root') return tree;
    const find = (n: RepertoireTreeNode): RepertoireTreeNode | null => {
      if (n.id === selectedNode.id) return n;
      for (const ch of n.children) {
        const hit = find(ch);
        if (hit) return hit;
      }
      return null;
    };
    return find(tree) ?? tree.children[0] ?? tree;
  }, [tree, selectedNode.id]);

  const orientation = course.side === 'white' ? 'w' : 'b';
  const primaryLineId = activeNode.lineIds[0] ?? course.lines[0]?.id;

  return (
    <div className="grid grid-cols-1 gap-3 lg:grid-cols-[minmax(0,380px)_minmax(0,1fr)]">
      {/* Board Preview for Selected Tree Node */}
      <div className="min-w-0 glass-card glass-card-strong p-3">
        <div className="mb-2 flex items-center justify-between gap-2 text-[10px]">
          <span className="flex min-w-0 items-center gap-1.5 font-bold text-slate-200">
            <GitBranch className="h-3.5 w-3.5 shrink-0 text-brilly" />
            <span className="truncate">
              {activeNode.ply > 0 ? formatMoveChip(activeNode) : 'Starting Position'}
            </span>
          </span>
          {activeNode.isUserMove && (
            <span className="shrink-0 rounded-full border border-teal-400/30 bg-teal-400/10 px-2 py-0.5 font-mono text-[9px] font-bold text-teal-200">
              {activeNode.recallPct !== null ? `Recall ${activeNode.recallPct}%` : 'Unlocked/New'}
            </span>
          )}
        </div>

        <div className="mx-auto w-full max-w-[min(100%,calc(100dvh-22rem))] lg:max-w-none">
          <ChessgroundBoard
            fen={activeNode.fen}
            orientation={orientation}
            lastMove={activeNode.lastMove}
            interactive={false}
            theme={boardTheme}
          />
        </div>

        {activeNode.planNote && (
          <p className="mt-2 rounded-xl border border-slate-800/90 bg-void/70 p-2 text-[11px] leading-snug text-slate-300">
            {activeNode.planNote}
          </p>
        )}

        <div className="mt-2.5 flex flex-wrap items-center gap-1.5">
          {primaryLineId && (
            <>
              <button
                type="button"
                onClick={() => onOpenLineWalkthrough(primaryLineId)}
                className="inline-flex flex-1 items-center justify-center gap-1 rounded-xl border border-teal-400/40 bg-teal-400/15 px-2.5 py-2 text-[11px] font-black text-teal-200 hover:bg-teal-400/25"
              >
                <Play className="h-3.5 w-3.5" /> Walkthrough
              </button>
              <button
                type="button"
                onClick={() => onDrillLine(primaryLineId)}
                className="inline-flex flex-1 items-center justify-center gap-1 rounded-xl border border-purple-400/40 bg-purple-500/15 px-2.5 py-2 text-[11px] font-black text-purple-200 hover:bg-purple-500/25"
              >
                <Orbit className="h-3.5 w-3.5" /> Drill Line
              </button>
            </>
          )}
        </div>
      </div>

      {/* Interactive Branching Tree */}
      <div className="min-w-0 glass-card p-3.5">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <div>
            <div className="text-[10px] font-black uppercase tracking-[0.14em] text-brilly">
              Course Move Tree
            </div>
            <p className="mt-0.5 text-[11px] text-slate-400">
              Tap any move to preview the position and FSRS memory strength across all {course.lines.length} lines.
            </p>
          </div>
          <div className="flex flex-wrap items-center gap-2 text-[9px] text-slate-400">
            <span className="inline-flex items-center gap-1"><span className="h-1.5 w-1.5 rounded-full bg-emerald-400" /> Strong</span>
            <span className="inline-flex items-center gap-1"><span className="h-1.5 w-1.5 rounded-full bg-amber-400" /> Learning</span>
            <span className="inline-flex items-center gap-1"><span className="h-1.5 w-1.5 rounded-full bg-purple-400" /> Due</span>
          </div>
        </div>

        <div className="mt-3 max-h-[26rem] overflow-y-auto rounded-xl border border-slate-800/80 bg-void/55 p-2.5 nice-scroll">
          {tree.children.length === 0 ? (
            <p className="py-6 text-center text-xs text-slate-500">No moves in this course yet.</p>
          ) : (
            tree.children.map((branch) => (
              <TreeBranchRow
                key={branch.id}
                node={branch}
                depth={0}
                selectedId={activeNode.id}
                onSelect={setSelectedNode}
              />
            ))
          )}
        </div>

        {activeNode.lineTitles.length > 0 && (
          <div className="mt-2.5 flex flex-wrap items-center gap-1 text-[10px]">
            <span className="text-slate-500">In lines:</span>
            {activeNode.lineIds.map((id, i) => (
              <button
                key={id}
                type="button"
                onClick={() => onOpenLineWalkthrough(id)}
                className="rounded-md border border-slate-800 bg-hull px-1.5 py-0.5 font-semibold text-slate-300 hover:border-teal-400/40 hover:text-teal-200"
              >
                {activeNode.lineTitles[i]}
              </button>
            ))}
          </div>
        )}
      </div>
    </div>
  );
};
