// test/screens/auth_screen_test.dart
//
// Vindara — AuthScreen Unit & Widget Tests
// Package: com.vindara.app

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vindara/screens/auth_screen.dart';

void main() {
  group('AuthScreen — Live Auth & Emergency Bypass', () {
    testWidgets('renders Sign In tab with email and password fields',
        (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: AuthScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Vindara'), findsOneWidget);
      expect(find.text('Decentralized Emergency Network'), findsOneWidget);
      expect(find.text('Sign In'), findsWidgets);
      expect(find.text('Create Account'), findsOneWidget);
      expect(find.byType(TextFormField), findsNWidgets(2)); // email, password
      expect(find.text('Continue Offline (Emergency Access)'), findsOneWidget);
    });

    testWidgets('switching to Create Account tab displays registration form',
        (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: AuthScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap 'Create Account' tab
      await tester.tap(find.text('Create Account'));
      await tester.pumpAndSettle();

      expect(find.text('Full Name / Display Name'), findsOneWidget);
      expect(find.text('Confirm Password'), findsOneWidget);
      expect(find.text('Password (min 6 characters)'), findsOneWidget);
    });

    testWidgets('Rule #10 — Strictly zero "SOS" strings appear on screen',
        (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: AuthScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final allTextWidgets = tester.widgetList<Text>(find.byType(Text));
      for (final text in allTextWidgets) {
        final data = text.data ?? text.textSpan?.toPlainText() ?? '';
        expect(
          data.toUpperCase().contains('SOS'),
          isFalse,
          reason: 'Forbidden "SOS" found in AuthScreen: "$data"',
        );
      }
    });

    testWidgets('validation triggers for empty fields on Sign In',
        (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: AuthScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Sign In button (the ElevatedButton, not the tab)
      final signInButton = find.widgetWithText(ElevatedButton, 'Sign In');
      expect(signInButton, findsOneWidget);
      await tester.tap(signInButton);
      await tester.pumpAndSettle();

      expect(find.text('Enter your email'), findsOneWidget);
      expect(find.text('Enter your password'), findsOneWidget);
    });
  });
}

