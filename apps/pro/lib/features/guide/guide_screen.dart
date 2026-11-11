import 'package:flutter/material.dart';

import '../../widgets/shared/design_system/colors.dart';
import '../../widgets/shared/design_system/tokens.dart';
import '../../widgets/shared/design_system/typography.dart';
import 'guide_content.dart';

/// The field guide: short, scoped explanations reachable from a reading.
///
/// It exists because the app can show a number and still leave the owner
/// guessing what it means. Every article answers one question, and each is
/// written to be read in under a minute.
class GuideScreen extends StatelessWidget {
  const GuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<JKBMSRColors>()!;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Guide'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(
            JKBMSRTokens.space16,
            JKBMSRTokens.space8,
            JKBMSRTokens.space16,
            JKBMSRTokens.space24,
          ),
          itemCount: guideArticles.length + 1,
          separatorBuilder: (_, __) => const SizedBox(height: JKBMSRTokens.space8),
          itemBuilder: (context, index) {
            if (index == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: JKBMSRTokens.space8),
                child: Text(
                  'Short answers to the questions a reading raises.',
                  style: JKBMSRTypography.bodySecondary.copyWith(
                    color: colors.textMuted,
                  ),
                ),
              );
            }
            final article = guideArticles[index - 1];
            return Card(
              clipBehavior: Clip.antiAlias,
              margin: EdgeInsets.zero,
              child: InkWell(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => GuideArticleScreen(article: article),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(JKBMSRTokens.space16),
                  child: Row(
                    children: [
                      Icon(Icons.menu_book_outlined,
                          size: 22, color: colors.accent),
                      const SizedBox(width: JKBMSRTokens.space16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              article.title,
                              style: JKBMSRTypography.body.copyWith(
                                fontWeight: FontWeight.w500,
                                color: colors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: JKBMSRTokens.space4),
                            Text(
                              article.summary,
                              style: JKBMSRTypography.bodySecondary.copyWith(
                                color: colors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: JKBMSRTokens.space8),
                      Icon(Icons.chevron_right,
                          size: 20, color: colors.textSubtle),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class GuideArticleScreen extends StatelessWidget {
  const GuideArticleScreen({super.key, required this.article});

  final GuideArticle article;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<JKBMSRColors>()!;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Guide'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            JKBMSRTokens.space24,
            JKBMSRTokens.space8,
            JKBMSRTokens.space24,
            JKBMSRTokens.space32,
          ),
          children: [
            Text(
              article.title,
              style: JKBMSRTypography.pageHeading.copyWith(
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: JKBMSRTokens.space8),
            Text(
              article.summary,
              style: JKBMSRTypography.bodySecondary.copyWith(
                color: colors.textMuted,
              ),
            ),
            for (final section in article.sections) ...[
              const SizedBox(height: JKBMSRTokens.space24),
              Text(
                section.heading,
                style: JKBMSRTypography.cardHeading.copyWith(
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: JKBMSRTokens.space8),
              for (final paragraph in section.paragraphs) ...[
                Text(
                  paragraph,
                  style: JKBMSRTypography.body.copyWith(
                    color: colors.textSecondary,
                    height: 1.55,
                  ),
                ),
                const SizedBox(height: JKBMSRTokens.space12),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
