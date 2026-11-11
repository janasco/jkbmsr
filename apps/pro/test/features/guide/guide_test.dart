// The guide: content invariants, and the list-to-article path.
//
// The content test is the one that matters. A guide is prose nobody re-reads
// before shipping, so the rules that always hold (an article has sections, a
// section has text, no em dashes in user-facing copy) are asserted rather than
// remembered.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jkbmsr_pro/features/guide/guide_content.dart';
import 'package:jkbmsr_pro/features/guide/guide_screen.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/theme.dart';

void main() {
  test('every article is complete and unique', () {
    final ids = <String>{};
    for (final article in guideArticles) {
      expect(ids.add(article.id), isTrue, reason: 'duplicate id ${article.id}');
      expect(article.title.trim(), isNotEmpty);
      expect(article.summary.trim(), isNotEmpty);
      expect(article.sections, isNotEmpty, reason: article.title);
      for (final section in article.sections) {
        expect(section.heading.trim(), isNotEmpty, reason: article.title);
        expect(section.paragraphs, isNotEmpty, reason: section.heading);
        for (final paragraph in section.paragraphs) {
          expect(paragraph.trim(), isNotEmpty, reason: section.heading);
        }
      }
    }
    // Six is the number of questions the app currently raises; a drop means an
    // article was deleted without deciding to.
    expect(guideArticles.length, greaterThanOrEqualTo(6));
  });

  test('user-facing copy carries no em dash', () {
    for (final article in guideArticles) {
      final text = [
        article.title,
        article.summary,
        for (final s in article.sections) ...[s.heading, ...s.paragraphs],
      ].join(' ');
      expect(text.contains('\u2014'), isFalse, reason: article.id);
      expect(text.contains('\u2013'), isFalse, reason: article.id);
    }
  });

  testWidgets('the list opens an article', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: JKBMSRTheme.darkTheme,
      home: const GuideScreen(),
    ));
    await tester.pump();

    final first = guideArticles.first;
    expect(find.text('Guide'), findsOneWidget);
    expect(find.text(first.title), findsOneWidget);

    await tester.tap(find.text(first.title));
    await tester.pumpAndSettle();

    // The article body, not just the title: the title is on both screens.
    expect(find.text(first.sections.first.heading), findsOneWidget);
    expect(find.text(first.sections.first.paragraphs.first), findsOneWidget);
  });
}
