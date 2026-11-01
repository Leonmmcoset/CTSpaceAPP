import 'package:flutter_test/flutter_test.dart';
import 'package:forum/core/markdown_codec.dart';

void main() {
  final codec = MarkdownCodec();
  test('rich text retains headings, Chinese, links and fenced code', () {
    const source =
        '# 标题\n\n**你好**，创作者。[链接](https://example.org)\n\n```\nconst x = 1;\n```\n';
    final result = codec.encode(codec.decode(source));
    expect(result, contains('标题'));
    expect(result, contains('**你好**'));
    expect(result, contains('https://example.org'));
    expect(result, contains('const x = 1;'));
  });
  test('unsupported Markdown selects source editing before conversion', () {
    expect(codec.requiresSource('| A | B |\n|---|---|\n| 1 | 2 |'), isTrue);
    expect(codec.requiresSource('> # nested heading'), isTrue);
    expect(codec.requiresSource('![描述](/a.png)'), isTrue);
    expect(codec.requiresSource('<video src="x"></video>'), isTrue);
    expect(codec.requiresSource('普通文字\n\n**粗体**'), isFalse);
  });
}
