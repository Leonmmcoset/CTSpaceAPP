import 'package:flutter_quill/flutter_quill.dart';
import 'package:markdown_quill/markdown_quill.dart';
import 'package:markdown/markdown.dart' as md;

class MarkdownCodec {
  final _toDelta = MarkdownToDelta(
    markdownDocument: md.Document(
      encodeHtml: false,
      extensionSet: md.ExtensionSet.gitHubFlavored,
    ),
  );
  final _toMarkdown = DeltaToMarkdown();
  Document decode(String source) => source.trim().isEmpty
      ? Document()
      : Document.fromDelta(_toDelta.convert(source));
  String encode(Document document) => _toMarkdown.convert(document.toDelta());
  // These structures do not round-trip losslessly through Quill's block model.
  bool requiresSource(String markdown) =>
      RegExp(r'^\s*\|.*\|\s*$', multiLine: true).hasMatch(markdown) ||
      RegExp(r'<\/?[a-zA-Z][^>]*>').hasMatch(markdown) ||
      RegExp(r'^>\s*(#|[-*+]\s|\d+\.)', multiLine: true).hasMatch(markdown) ||
      RegExp(r'!\[[^\]]+\]\(').hasMatch(markdown);
}
