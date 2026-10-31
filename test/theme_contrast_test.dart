import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sign_voice/core/theme.dart';

double contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return (math.max(x, y) + .05) / (math.min(x, y) + .05);
}

void main() {
  test('workspace and account text meet contrast in light and dark themes', () {
    for (final dark in [false, true]) {
      final theme = makeTheme(dark: dark, highContrast: false);
      final scheme = theme.colorScheme;
      for (final surface in [
        scheme.surface,
        theme.scaffoldBackgroundColor,
        scheme.surfaceContainerHighest,
      ]) {
        for (final foreground in [scheme.onSurface, scheme.onSurfaceVariant]) {
          expect(
            contrast(foreground, surface),
            greaterThanOrEqualTo(4.5),
            reason: 'dark=$dark foreground=$foreground surface=$surface',
          );
        }
      }
      expect(
        contrast(scheme.onPrimaryContainer, scheme.primaryContainer),
        greaterThanOrEqualTo(4.5),
      );
      expect(contrast(scheme.error, scheme.surface), greaterThanOrEqualTo(4.5));
    }
  });
  test('primary links and labels remain readable on mobile surfaces in both themes', () {
    for (final dark in [false, true]) {
      for (final highContrast in [false, true]) {
        final scheme = makeTheme(
          dark: dark,
          highContrast: highContrast,
        ).colorScheme;
        expect(
          contrast(scheme.primary, scheme.surface),
          greaterThanOrEqualTo(4.5),
          reason: 'dark=$dark highContrast=$highContrast',
        );
        expect(
          contrast(scheme.onPrimary, scheme.primary),
          greaterThanOrEqualTo(4.5),
        );
      }
    }
  });
}
