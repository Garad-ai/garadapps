import { useColorScheme } from 'react-native';

// Mirrors the Chat Pro web tokens in Garad_ai/frontend/src/index.css.
const light = {
  background: '#f8f8f6',
  surface: '#f6f6f3',
  surfaceStrong: '#ecece8',
  text: '#1d2421',
  muted: '#69716d',
  faint: '#939a96',
  line: '#dedfda',
  brand: '#514cff',
  brandText: '#ffffff',
  brandSoft: '#efefff',
  danger: '#c62828',
  userBubble: '#514cff',
  userBubbleText: '#ffffff',
};

const dark: typeof light = {
  background: '#111513',
  surface: '#181d1b',
  surfaceStrong: '#202622',
  text: '#edf0ed',
  muted: '#a1aaa5',
  faint: '#7a847f',
  line: '#333b37',
  brand: '#7773ff',
  brandText: '#ffffff',
  brandSoft: '#29284b',
  danger: '#ef5350',
  userBubble: '#514cff',
  userBubbleText: '#ffffff',
};

export type Palette = typeof light;

export function usePalette(): Palette {
  return useColorScheme() === 'dark' ? dark : light;
}

export function useIsDark(): boolean {
  return useColorScheme() === 'dark';
}
