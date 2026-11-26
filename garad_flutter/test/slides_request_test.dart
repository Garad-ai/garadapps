import 'package:flutter_test/flutter_test.dart';
import 'package:garad_ai/api/models.dart';
import 'package:garad_ai/slides_request.dart';

/// Slides asked for on DeepSeek go with a Claude model: only Claude's document engine builds decks.
void main() {
  const deepseek = ChatModelInfo(id: 'deepseek-v4-flash', name: 'DeepSeek V4 Flash', provider: 'deep_seek');
  const haiku = ChatModelInfo(id: 'claude-haiku-5-5', name: 'Claude Haiku 5.5', provider: 'anthropic');
  const sonnet = ChatModelInfo(id: 'claude-sonnet-5-5', name: 'Claude Sonnet 5.5', provider: 'anthropic');
  const lockedSonnet = ChatModelInfo(
    id: 'claude-sonnet-5-5',
    name: 'Claude Sonnet 5.5',
    provider: 'anthropic',
    locked: true,
  );

  test('slide requests are recognised, misspellings included', () {
    for (final text in [
      'Make as slides',
      'Make presantion online business idea',
      'make a power point about Somalia',
      'create a presentation for my class',
      'slides please',
      'Slides ka dhig',
    ]) {
      expect(asksForSlides(text), isTrue, reason: text);
    }
    for (final text in [
      'The presentation of the results was clear and useful for everyone',
      'what is a business idea',
      'I want to present my idea tomorrow',
    ]) {
      expect(asksForSlides(text), isFalse, reason: text);
    }
  });

  test('misspelled file words are sent spelled right', () {
    expect(withCorrectedFileWords('Make presantion online business idea'), 'Make presentation online business idea');
    expect(withCorrectedFileWords('Is power point'), 'Is PowerPoint');
    expect(withCorrectedFileWords('Make as sildes'), 'Make as slides');
    expect(withCorrectedFileWords('make presantions'), 'make presentations');
    for (final text in ['I want to present my idea', 'a fair representation', 'the car slid', 'make slides']) {
      expect(withCorrectedFileWords(text), text);
    }
  });

  test('on DeepSeek a deck goes with the cheapest usable Claude', () {
    expect(claudeModelForSlides('Make as slides', [deepseek, sonnet, haiku], 'deepseek-v4-flash'), 'claude-haiku-5-5');
    expect(claudeModelForSlides('Make as slides', [deepseek, lockedSonnet], 'deepseek-v4-flash'), isNull,
        reason: 'no usable Claude: keep the chosen model');
    expect(claudeModelForSlides('Make as slides', [deepseek, haiku], 'claude-haiku-5-5'), isNull,
        reason: 'already Claude');
    expect(claudeModelForSlides('hello there', [deepseek, haiku], 'deepseek-v4-flash'), isNull);
  });
}
