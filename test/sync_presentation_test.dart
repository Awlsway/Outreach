import 'package:ansvk_outreach/sync/synthetic_review_export.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'certificate_renewal_ui_test_support.dart';

void main() {
  RenewalUiHarness? harness;
  void testUi(String description, Future<void> Function(WidgetTester) action) {
    testWidgets(description, (tester) async {
      try {
        await action(tester);
      } finally {
        await tester.pumpWidget(const SizedBox());
        final h = harness;
        harness = null;
        h?.session.dispose();
        if (h != null) await tester.runAsync(h.dispose);
      }
    });
  }

  Future<RenewalUiHarness> open(
    WidgetTester tester, {
    bool paired = true,
  }) async {
    final h = RenewalUiHarness();
    harness = h;
    await tester.runAsync(() => h.init(paired: paired));
    await tester.pumpWidget(h.app());
    await tapRenewalUi(tester, 'open-sync-status');
    await waitRenewalUi(
      tester,
      h,
      () => find
          .byKey(const ValueKey('sync-pairing-status'))
          .evaluate()
          .isNotEmpty,
    );
    return h;
  }

  Future<void> show(WidgetTester tester, String key) async {
    await tester.scrollUntilVisible(
      find.byKey(ValueKey(key)),
      160,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
  }

  testUi(
    'main Sync summary and grouped tools preserve data without connecting',
    (tester) async {
      final h = await open(tester);
      expect(find.text('Phone paired with dashboard'), findsOneWidget);
      expect(find.text('No successful sync yet'), findsOneWidget);
      expect(find.text('Address'), findsNothing);
      expect(
        find.byKey(const ValueKey('check-dashboard-access')),
        findsNothing,
      );
      if (SyntheticReviewExport.enabled) {
        await show(tester, 'prepare-sync-batches');
      }
      expect(
        find.byKey(const ValueKey('prepare-sync-batches')),
        SyntheticReviewExport.enabled ? findsOneWidget : findsNothing,
      );
      if (!SyntheticReviewExport.enabled) {
        await show(tester, 'normal-sync');
      }
      expect(
        find.byKey(const ValueKey('normal-sync')),
        SyntheticReviewExport.enabled ? findsNothing : findsOneWidget,
      );
      await show(tester, 'open-certificate-renewal');
      expect(
        find.byKey(const ValueKey('open-certificate-renewal')),
        findsOneWidget,
      );
      await show(tester, 'sync-technical-toggle');
      await tapRenewalUi(tester, 'sync-technical-toggle');
      await tester.pumpAndSettle();
      expect(find.text('Address'), findsOneWidget);
      expect(find.text('Retention safety'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('prepare-sync-batches')),
        findsOneWidget,
      );
      await tapRenewalUi(tester, 'sync-technical-toggle');
      await tester.pumpAndSettle();
      expect(find.text('Address'), findsNothing);
      expect(h.paths, isEmpty);
      expect(h.peers, isEmpty);
      await tester.runAsync(h.preserved);
    },
  );

  testUi('unpaired QR action stays outside details and Sync stays disabled', (
    tester,
  ) async {
    final h = await open(tester, paired: false);
    expect(find.text('Phone not paired with dashboard'), findsOneWidget);
    await show(tester, 'scan-dashboard-qr');
    expect(
      find.byKey(const ValueKey('scan-dashboard-qr')).hitTestable(),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('open-certificate-renewal')),
      findsNothing,
    );
    if (!SyntheticReviewExport.enabled) {
      await show(tester, 'normal-sync');
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('normal-sync')))
            .onPressed,
        isNull,
      );
    }
    expect(find.text('Address'), findsNothing);
    expect(h.paths, isEmpty);
    await tester.runAsync(h.preserved);
  });

  testUi(
    'narrow large-text Sync can reach actions and conceal details on lock',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.8;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final h = await open(tester);
      if (!SyntheticReviewExport.enabled) {
        await show(tester, 'normal-sync');
        expect(
          find.byKey(const ValueKey('normal-sync')).hitTestable(),
          findsOneWidget,
        );
      }
      await show(tester, 'view-pending-changes');
      expect(
        find.byKey(const ValueKey('view-pending-changes')).hitTestable(),
        findsOneWidget,
      );
      await show(tester, 'sync-technical-toggle');
      await tapRenewalUi(tester, 'sync-technical-toggle');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Address'), findsOneWidget);
      h.session.lock();
      await tester.pump();
      expect(find.text('Address').hitTestable(), findsNothing);
      expect(
        find.byKey(const ValueKey('normal-sync')).hitTestable(),
        findsNothing,
      );
      expect(h.paths, isEmpty);
      await tester.runAsync(h.preserved);
    },
  );
}
