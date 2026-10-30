import { Fragment, ReactNode } from 'react';
import { Platform, StyleSheet, Text, View } from 'react-native';

import { Palette, serif, usePalette } from '@/lib/theme';

/**
 * A small Markdown renderer covering what chat replies typically use:
 * headings, bullet/numbered lists, fenced code, inline code, bold and italics.
 */
export function Markdown({ text }: { text: string }) {
  const c = usePalette();
  const blocks = parseBlocks(text);

  return (
    <View style={styles.container}>
      {blocks.map((block, index) => {
        if (block.kind === 'code') {
          return (
            <View key={index} style={[styles.code, { backgroundColor: c.surfaceStrong }]}>
              <Text selectable style={[styles.codeText, { color: c.text }]}>
                {block.text}
              </Text>
            </View>
          );
        }
        if (block.kind === 'heading') {
          return (
            <Text key={index} selectable style={[styles.heading, { color: c.text }]}>
              {inline(block.text, c)}
            </Text>
          );
        }
        if (block.kind === 'list') {
          return (
            <View key={index} style={styles.list}>
              {block.items.map((item, itemIndex) => (
                <View key={itemIndex} style={styles.listItem}>
                  <Text style={[styles.body, { color: c.muted }]}>
                    {block.ordered ? `${itemIndex + 1}.` : '•'}
                  </Text>
                  <Text selectable style={[styles.body, styles.listText, { color: c.text }]}>
                    {inline(item, c)}
                  </Text>
                </View>
              ))}
            </View>
          );
        }
        return (
          <Text key={index} selectable style={[styles.body, { color: c.text }]}>
            {inline(block.text, c)}
          </Text>
        );
      })}
    </View>
  );
}

type Block =
  | { kind: 'paragraph' | 'heading' | 'code'; text: string }
  | { kind: 'list'; ordered: boolean; items: string[] };

function parseBlocks(source: string): Block[] {
  const lines = source.replace(/\r\n/g, '\n').split('\n');
  const blocks: Block[] = [];
  let paragraph: string[] = [];

  const flush = () => {
    if (paragraph.length) blocks.push({ kind: 'paragraph', text: paragraph.join('\n') });
    paragraph = [];
  };

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];

    if (line.trimStart().startsWith('```')) {
      flush();
      const code: string[] = [];
      i++;
      while (i < lines.length && !lines[i].trimStart().startsWith('```')) code.push(lines[i++]);
      blocks.push({ kind: 'code', text: code.join('\n') });
      continue;
    }

    const heading = /^#{1,6}\s+(.*)$/.exec(line);
    if (heading) {
      flush();
      blocks.push({ kind: 'heading', text: heading[1] });
      continue;
    }

    const bullet = /^\s*[-*•]\s+(.*)$/.exec(line);
    const numbered = /^\s*\d+[.)]\s+(.*)$/.exec(line);
    if (bullet || numbered) {
      flush();
      const ordered = Boolean(numbered);
      const item = (bullet ?? numbered)![1];
      const last = blocks[blocks.length - 1];
      if (last && last.kind === 'list' && last.ordered === ordered) last.items.push(item);
      else blocks.push({ kind: 'list', ordered, items: [item] });
      continue;
    }

    if (line.trim() === '') flush();
    else paragraph.push(line);
  }
  flush();
  return blocks;
}

function inline(text: string, c: Palette): ReactNode {
  const parts = text.split(/(\*\*[^*]+\*\*|`[^`]+`|\*[^*\s][^*]*\*)/g);
  return parts.map((part, index) => {
    if (part.startsWith('**') && part.endsWith('**') && part.length > 4) {
      return (
        <Text key={index} style={styles.bold}>
          {part.slice(2, -2)}
        </Text>
      );
    }
    if (part.startsWith('`') && part.endsWith('`') && part.length > 2) {
      return (
        <Text key={index} style={[styles.inlineCode, { backgroundColor: c.surfaceStrong }]}>
          {part.slice(1, -1)}
        </Text>
      );
    }
    if (part.startsWith('*') && part.endsWith('*') && part.length > 2) {
      return (
        <Text key={index} style={styles.italic}>
          {part.slice(1, -1)}
        </Text>
      );
    }
    return <Fragment key={index}>{part}</Fragment>;
  });
}

const mono = Platform.select({ ios: 'Menlo', default: 'monospace' });

const styles = StyleSheet.create({
  container: { gap: 10 },
  body: { fontFamily: serif, fontSize: 17, lineHeight: 26 },
  heading: { fontFamily: serif, fontSize: 19, lineHeight: 27, fontWeight: '700' },
  list: { gap: 4 },
  listItem: { flexDirection: 'row', gap: 8 },
  listText: { flex: 1 },
  code: { borderRadius: 10, padding: 12 },
  codeText: { fontFamily: mono, fontSize: 13, lineHeight: 19 },
  inlineCode: { fontFamily: mono, fontSize: 14 },
  bold: { fontWeight: '700' },
  italic: { fontStyle: 'italic' },
});
