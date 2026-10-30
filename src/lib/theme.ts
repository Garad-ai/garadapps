import { Platform, useColorScheme } from 'react-native';

// Warm, paper-like neutrals in the style of the Claude app, with Garad's indigo as the accent.
const light = {
  background: '#faf9f5',
  surface: '#f2f0e8',
  surfaceStrong: '#e9e6dc',
  card: '#ffffff',
  text: '#1f1e1b',
  muted: '#6b6a64',
  faint: '#9a988f',
  line: '#e3e0d6',
  brand: '#514cff',
  brandText: '#ffffff',
  brandSoft: '#ecebff',
  danger: '#b3261e',
  userBubble: '#efece3',
};

const dark: typeof light = {
  background: '#262624',
  surface: '#1f1e1d',
  surfaceStrong: '#34332f',
  card: '#30302e',
  text: '#f5f4ef',
  muted: '#b7b5ab',
  faint: '#8a887f',
  line: '#3d3c38',
  brand: '#7773ff',
  brandText: '#ffffff',
  brandSoft: '#2f2e4d',
  danger: '#f2a29b',
  userBubble: '#141413',
};

export type Palette = typeof light;

export function usePalette(): Palette {
  return useColorScheme() === 'dark' ? dark : light;
}

export function useIsDark(): boolean {
  return useColorScheme() === 'dark';
}

/** Serif face for greetings and assistant replies, as in the Claude app. */
export const serif = Platform.select({ ios: 'Georgia', android: 'serif', default: 'Georgia, serif' });
