import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

// 游戏库条目
export interface GameItem {
  id: string;
  name: string;
  file: string;
  last: number;
}

// 设置键
export const SET_GUIDE = 'guide_seen';
export const SET_PAD = 'pad_visible';
export const SET_SHARP = 'pixel_sharp';
export const SET_FF = 'ff_speed';

function prefsOf(ctx: common.Context): preferences.Preferences {
  return preferences.getPreferencesSync(ctx, { name: 'gb_cfg' });
}

export function loadGames(ctx: common.Context): GameItem[] {
  const out: GameItem[] = [];
  try {
    const raw = prefsOf(ctx).getSync('games', '') as string;
    if (raw.length === 0) {
      return out;
    }
    const lines = raw.split('\n');
    for (let i = 0; i < lines.length; i++) {
      const f = lines[i].split('|');
      if (f.length >= 4) {
        const it: GameItem = { id: f[0], name: f[1], file: f[2], last: Number(f[3]) };
        out.push(it);
      }
    }
  } catch (err) {
  }
  return out;
}

export function saveGames(ctx: common.Context, list: GameItem[]): void {
  const lines: string[] = [];
  for (let i = 0; i < list.length; i++) {
    const g = list[i];
    lines.push(`${g.id}|${g.name}|${g.file}|${g.last}`);
  }
  try {
    const p = prefsOf(ctx);
    p.putSync('games', lines.join('\n'));
    p.flush();
  } catch (err) {
  }
}

export function addGame(ctx: common.Context, name: string, file: string): GameItem {
  const it: GameItem = {
    id: Date.now().toString(),
    name: name.replace('|', '_').replace('\n', ' '),
    file: file,
    last: Date.now()
  };
  const list = loadGames(ctx);
  list.push(it);
  saveGames(ctx, list);
  return it;
}

export function touchGame(ctx: common.Context, id: string): void {
  if (id.length === 0) {
    return;
  }
  const list = loadGames(ctx);
  for (let i = 0; i < list.length; i++) {
    if (list[i].id === id) {
      list[i].last = Date.now();
    }
  }
  saveGames(ctx, list);
}

export function removeGame(ctx: common.Context, id: string): GameItem[] {
  const list = loadGames(ctx);
  const out: GameItem[] = [];
  for (let i = 0; i < list.length; i++) {
    if (list[i].id !== id) {
      out.push(list[i]);
    }
  }
  saveGames(ctx, out);
  return out;
}

export function getBool(ctx: common.Context, key: string, def: boolean): boolean {
  try {
    return prefsOf(ctx).getSync(key, def) as boolean;
  } catch (err) {
    return def;
  }
}

export function setBool(ctx: common.Context, key: string, v: boolean): void {
  try {
    const p = prefsOf(ctx);
    p.putSync(key, v);
    p.flush();
  } catch (err) {
  }
}

export function getNum(ctx: common.Context, key: string, def: number): number {
  try {
    return prefsOf(ctx).getSync(key, def) as number;
  } catch (err) {
    return def;
  }
}

export function setNum(ctx: common.Context, key: string, v: number): void {
  try {
    const p = prefsOf(ctx);
    p.putSync(key, v);
    p.flush();
  } catch (err) {
  }
}

export function fmtLast(ts: number): string {
  if (ts <= 0) {
    return '尚未游玩';
  }
  const d = new Date(ts);
  const p2 = (n: number): string => {
    return n < 10 ? '0' + n : n.toString();
  };
  return `${d.getMonth() + 1}月${d.getDate()}日 ${p2(d.getHours())}:${p2(d.getMinutes())}`;
}
