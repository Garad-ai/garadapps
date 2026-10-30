import { SymbolView, SymbolViewProps } from 'expo-symbols';
import { ColorValue } from 'react-native';

const ICONS = {
  menu: { ios: 'line.3.horizontal', android: 'menu', web: 'menu' },
  newChat: { ios: 'square.and.pencil', android: 'edit_square', web: 'edit_square' },
  send: { ios: 'arrow.up', android: 'arrow_upward', web: 'arrow_upward' },
  stop: { ios: 'stop.fill', android: 'stop', web: 'stop' },
  copy: { ios: 'doc.on.doc', android: 'content_copy', web: 'content_copy' },
  check: { ios: 'checkmark', android: 'check', web: 'check' },
  search: { ios: 'magnifyingglass', android: 'search', web: 'search' },
  images: { ios: 'photo.on.rectangle', android: 'image', web: 'image' },
  chat: { ios: 'bubble.left', android: 'chat_bubble', web: 'chat_bubble' },
  chevron: { ios: 'chevron.right', android: 'chevron_right', web: 'chevron_right' },
} satisfies Record<string, SymbolViewProps['name']>;

export type IconName = keyof typeof ICONS;

export function Icon({ name, color, size = 22 }: { name: IconName; color: ColorValue; size?: number }) {
  return <SymbolView name={ICONS[name]} tintColor={color} size={size} />;
}
