/**
 * Gearboy native module (libgearboy.so) — NAPI interface.
 * Key codes for setKey: 0=UP 1=DOWN 2=LEFT 3=RIGHT 4=A 5=B 6=SELECT 7=START
 */
export const loadRom: (romBytes: ArrayBuffer, romName?: string) => boolean;
export const runFrame: () => void;
export const setKey: (key: number, pressed: boolean) => void;
export const saveState: (slot: number) => boolean;
export const loadState: (slot: number) => boolean;
export const reset: () => boolean;
export const setSaveDir: (dir: string) => void;
export const isRomLoaded: () => boolean;
export const getFramePixels: () => ArrayBuffer;
export const getAudioSamples: () => ArrayBuffer;
export const saveRam: () => boolean;
export const loadRam: () => boolean;
