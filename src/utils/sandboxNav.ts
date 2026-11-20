export interface SandboxNavMove {
  san: string;
  uci: string;
  from: string;
  to: string;
}

export interface SandboxNavState {
  basePly: number;
  moves: SandboxNavMove[];
  cursor: number;
}

export function stepSandboxNav(
  state: SandboxNavState,
  delta: -1 | 1,
  totalPlies: number
): SandboxNavState {
  if (delta === -1) {
    if (state.cursor > 0) {
      return { ...state, cursor: state.cursor - 1 };
    }
    if (state.basePly > 0) {
      return { basePly: state.basePly - 1, moves: [], cursor: 0 };
    }
    return state;
  }

  // delta === 1 (Forward)
  if (state.cursor < state.moves.length) {
    return { ...state, cursor: state.cursor + 1 };
  }
  if (state.moves.length === 0 && state.basePly < totalPlies) {
    return { basePly: state.basePly + 1, moves: [], cursor: 0 };
  }
  return state;
}

export function jumpSandboxEdge(
  state: SandboxNavState,
  edge: 'first' | 'last',
  totalPlies: number
): SandboxNavState {
  if (edge === 'first') {
    if (state.cursor > 0) {
      return { ...state, cursor: 0 };
    }
    if (state.basePly > 0) {
      return { basePly: 0, moves: [], cursor: 0 };
    }
    return state;
  }

  // edge === 'last'
  if (state.cursor < state.moves.length) {
    return { ...state, cursor: state.moves.length };
  }
  if (state.moves.length === 0 && state.basePly < totalPlies) {
    return { basePly: totalPlies, moves: [], cursor: 0 };
  }
  return state;
}

export function appendSandboxMoves(
  state: SandboxNavState,
  incoming: SandboxNavMove[]
): SandboxNavState {
  if (incoming.length === 0) return state;
  const prefix = state.moves.slice(0, state.cursor);
  const nextMoves = [...prefix, ...incoming];
  return {
    ...state,
    moves: nextMoves,
    cursor: nextMoves.length,
  };
}
