import 'dart:async';
import 'package:ansvk_outreach/sync/certificate_renewal_review.dart';
import 'package:ansvk_outreach/sync/certificate_renewal_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'certificate_renewal_ui_test_support.dart';

void main() {
  RenewalUiHarness? activeHarness;
  void testUi(String description, Future<void> Function(WidgetTester) action) {
    testWidgets(description, (tester) async {
      try {
        await action(tester);
      } finally {
        await tester.pumpWidget(const SizedBox());
        final h = activeHarness;
        activeHarness = null;
        h?.session.dispose();
        if (h != null) {
          await tester.runAsync(h.dispose);
        }
      }
    });
  }

  Future<RenewalUiHarness> setup(
    WidgetTester tester, {
    bool paired = true,
  }) async {
    final h = RenewalUiHarness();
    activeHarness = h;
    await tester.runAsync(() => h.init(paired: paired));
    return h;
  }

  Future<void> approve(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Continue renewal'));
    await tester.tap(find.text('Continue renewal'));
    await tester.pump();
  }

  testUi('unpaired phone keeps QR pairing and has no renewal entry', (
    tester,
  ) async {
    final h = await setup(tester, paired: false);
    await tester.pumpWidget(h.app());
    await tapRenewalUi(tester, 'open-sync-status');
    await waitRenewalUi(
      tester,
      h,
      () =>
          find.byKey(const ValueKey('scan-dashboard-qr')).evaluate().isNotEmpty,
    );
    expect(
      find.byKey(const ValueKey('open-certificate-renewal')),
      findsNothing,
    );
    expect(h.paths, isEmpty);
    await tester.runAsync(h.preserved);
  });
  testUi(
    'actual app shell reviews, renews and uses the new pin for ordinary Sync',
    (tester) async {
      final h = await setup(tester);
      await openRenewalUi(tester, h);
      expect(h.paths, isEmpty);
      await reviewRenewalUi(tester, h);
      expect(h.paths, isEmpty);
      await approve(tester);
      await waitRenewalUi(
        tester,
        h,
        () => find.text('Certificate renewal complete.').evaluate().isNotEmpty,
      );
      expect(h.paths, [
        '/api/v1/certificate-renewals/claim',
        '/api/v1/certificate-renewals/confirm',
      ]);
      await tester.runAsync(h.preserved);
      await tester.tap(find.byType(BackButton).first);
      await waitRenewalUi(
        tester,
        h,
        () => find.byKey(const ValueKey('normal-sync')).evaluate().isNotEmpty,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('normal-sync')))
            .onPressed,
        isNotNull,
      );
      await tapRenewalUi(tester, 'normal-sync');
      await waitRenewalUi(
        tester,
        h,
        () => find
            .textContaining('Sync complete. Dashboard confirmed')
            .evaluate()
            .isNotEmpty,
        maxPumps: 400,
      );
      expect(h.uploads, 1);
      expect(await tester.runAsync(h.credentials.read), 'synthetic-credential');
      expect(await tester.runAsync(h.repo.appIdentity), h.identity);
      expect(await tester.runAsync(h.repo.pendingOperations), isEmpty);
    },
  );
  testUi('scanner and review Cancel preserve data without a network claim', (
    tester,
  ) async {
    final h = await setup(tester);
    await openRenewalUi(tester, h);
    await tapRenewalUi(tester, 'scan-renewal-qr');
    await tester.tap(find.byType(BackButton));
    await waitRenewalUi(
      tester,
      h,
      () => find.byKey(const ValueKey('scan-renewal-qr')).evaluate().isNotEmpty,
    );
    await reviewRenewalUi(tester, h);
    await tester.tap(find.text('Cancel'));
    await waitRenewalUi(
      tester,
      h,
      () => find.byKey(const ValueKey('scan-renewal-qr')).evaluate().isNotEmpty,
    );
    expect(h.paths, isEmpty);
    expect(await tester.runAsync(h.history), isEmpty);
    await tester.runAsync(h.preserved);
  });
  for (final bad in ['ansvk-outreach://pair/v1#invalid', 'SECRET-invalid-QR']) {
    testUi(
      'invalid or wrong-purpose scan shows safe error without raw input: $bad',
      (tester) async {
        final h = await setup(tester);
        h.qr = bad;
        await openRenewalUi(tester, h);
        await tapRenewalUi(tester, 'scan-renewal-qr');
        await tapRenewalUi(tester, 'emit-synthetic-qr');
        await waitRenewalUi(
          tester,
          h,
          () =>
              find.byKey(const ValueKey('renewal-error')).evaluate().isNotEmpty,
        );
        expect(find.textContaining(bad), findsNothing);
        expect(find.byType(CertificateRenewalReview), findsNothing);
        expect(h.paths, isEmpty);
        expect(await tester.runAsync(h.history), isEmpty);
        await tester.runAsync(h.preserved);
      },
    );
  }
  for (final confirmation in [false, true]) {
    testUi(
      'saved pending phase $confirmation resumes after leaving and reopening',
      (tester) async {
        final h = await setup(tester);
        await tester.runAsync(() => h.pending(confirmation: confirmation));
        await openRenewalUi(tester, h);
        expect(find.byKey(const ValueKey('resume-renewal')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('scan-renewal-qr')),
          confirmation ? findsOneWidget : findsNothing,
        );
        await tester.tap(find.byType(BackButton).first);
        await waitRenewalUi(
          tester,
          h,
          () => find.byKey(const ValueKey('normal-sync')).evaluate().isNotEmpty,
        );
        expect(
          tester
              .widget<FilledButton>(find.byKey(const ValueKey('normal-sync')))
              .onPressed,
          isNull,
        );
        expect(
          find.byKey(const ValueKey('renewal-blocks-sync')),
          findsOneWidget,
        );
        await tester.pumpWidget(const SizedBox());
        await openRenewalUi(tester, h);
        await tapRenewalUi(tester, 'resume-renewal');
        await waitRenewalUi(
          tester,
          h,
          () =>
              find.text('Certificate renewal complete.').evaluate().isNotEmpty,
        );
        expect(
          (await tester.runAsync(h.history))!.single['state'],
          'confirmed',
        );
        await tester.runAsync(h.preserved);
      },
    );
  }
  for (final path in ['claim', 'confirm']) {
    testUi(
      'Stop during $path keeps durable progress and permits exact Resume',
      (tester) async {
        final h = await setup(tester);
        final held = Completer<void>();
        if (path == 'claim') {
          h.holdClaim = held;
        } else {
          h.holdConfirm = held;
        }
        await openRenewalUi(tester, h);
        await reviewRenewalUi(tester, h);
        await approve(tester);
        await waitRenewalUi(
          tester,
          h,
          () => h.paths.any((p) => p.endsWith('/$path')),
        );
        await tester.tap(find.byType(BackButton).first);
        await tester.pump();
        expect(find.byType(CertificateRenewalPage), findsOneWidget);
        await tapRenewalUi(tester, 'stop-renewal');
        await waitRenewalUi(
          tester,
          h,
          () => find
              .byKey(const ValueKey('resume-renewal'))
              .evaluate()
              .isNotEmpty,
        );
        expect(
          find.text('Renewal stopped. Saved progress and records were kept.'),
          findsOneWidget,
        );
        expect(
          (await tester.runAsync(h.history))!.single['state'],
          path == 'claim' ? 'claim_pending' : 'confirmation_pending',
        );
        expect(h.peers.last.closed, true);
        held.complete();
        await flushRenewalUi(tester, h);
        await tapRenewalUi(tester, 'resume-renewal');
        await waitRenewalUi(
          tester,
          h,
          () =>
              find.text('Certificate renewal complete.').evaluate().isNotEmpty,
        );
        await tester.runAsync(h.preserved);
      },
    );
  }
  testUi(
    'lock removes a reviewed QR; unlock rereads state without reusing approval',
    (tester) async {
      final h = await setup(tester);
      await openRenewalUi(tester, h);
      await reviewRenewalUi(tester, h);
      h.session.lock();
      await tester.pump();
      expect(find.text('App locked'), findsOneWidget);
      expect(find.byType(CertificateRenewalReview), findsNothing);
      await tester.runAsync(() => h.session.unlock('password1'));
      await waitRenewalUi(
        tester,
        h,
        () =>
            find.byKey(const ValueKey('scan-renewal-qr')).evaluate().isNotEmpty,
      );
      expect(find.byType(CertificateRenewalReview), findsNothing);
      expect(h.paths, isEmpty);
      await tester.runAsync(h.preserved);
    },
  );
  testUi('background removes the embedded camera and ignores its late scan', (
    tester,
  ) async {
    final h = await setup(tester);
    await openRenewalUi(tester, h);
    await tapRenewalUi(tester, 'scan-renewal-qr');
    final lateScan = h.lastScanned!;
    h.session.setForeground(false);
    await tester.pump();
    expect(find.text('Synthetic scanner'), findsNothing);
    lateScan(h.qr);
    h.session.setForeground(true);
    await waitRenewalUi(
      tester,
      h,
      () => find.byKey(const ValueKey('scan-renewal-qr')).evaluate().isNotEmpty,
    );
    expect(find.byType(CertificateRenewalReview), findsNothing);
    expect(h.paths, isEmpty);
    await tester.runAsync(h.preserved);
  });
  testUi(
    'lock during claim cannot commit a late receipt; authenticated Resume recovers',
    (tester) async {
      final h = await setup(tester);
      h.holdClaim = Completer<void>();
      await openRenewalUi(tester, h);
      await reviewRenewalUi(tester, h);
      await approve(tester);
      await waitRenewalUi(
        tester,
        h,
        () => h.paths.any((p) => p.endsWith('/claim')),
      );
      h.session.lock();
      await tester.pump();
      h.holdClaim!.complete();
      for (var i = 0; i < 10; i++) {
        await flushRenewalUi(tester, h);
      }
      expect(find.text('App locked'), findsOneWidget);
      expect(
        (await tester.runAsync(h.history))!.single['state'],
        'claim_pending',
      );
      await tester.runAsync(() => h.session.unlock('password1'));
      await waitRenewalUi(
        tester,
        h,
        () =>
            find.byKey(const ValueKey('resume-renewal')).evaluate().isNotEmpty,
      );
      await tapRenewalUi(tester, 'resume-renewal');
      await waitRenewalUi(
        tester,
        h,
        () => find.text('Certificate renewal complete.').evaluate().isNotEmpty,
      );
      await tester.runAsync(h.preserved);
    },
  );
  testUi('invalid receipt reports a clear error and leaves Sync blocked', (
    tester,
  ) async {
    final h = await setup(tester);
    h.corruptReceipt = true;
    await openRenewalUi(tester, h);
    await reviewRenewalUi(tester, h);
    await approve(tester);
    await waitRenewalUi(
      tester,
      h,
      () => find.byKey(const ValueKey('resume-renewal')).evaluate().isNotEmpty,
    );
    expect(find.byKey(const ValueKey('renewal-error')), findsOneWidget);
    expect(
      (await tester.runAsync(h.history))!.single['state'],
      'claim_pending',
    );
    expect(find.byKey(const ValueKey('scan-renewal-qr')), findsNothing);
    await tester.runAsync(h.preserved);
  });
  testUi(
    'missing saved authority fails closed with Retry, no camera or reset',
    (tester) async {
      final h = await setup(tester);
      await tester.runAsync(
        () => h.db.connection.update('initial_certificate_trust', {
          'state': 'bootstrap_pending',
          'bootstrap_json': null,
        }),
      );
      h.original = (await tester.runAsync(h.snapshot))!;
      await tester.pumpWidget(
        MaterialApp(
          home: CertificateRenewalPage(
            session: h.session,
            trust: h.trust,
            onBack: () {},
            onBusyChanged: (_) {},
            scannerBuilder: h.scanner,
          ),
        ),
      );
      await waitRenewalUi(
        tester,
        h,
        () => find
            .byKey(const ValueKey('retry-renewal-status'))
            .evaluate()
            .isNotEmpty,
      );
      expect(find.byKey(const ValueKey('scan-renewal-qr')), findsNothing);
      expect(h.paths, isEmpty);
      await tester.runAsync(h.preserved);
    },
  );
  testUi('scanner callback after page disposal cannot approve or mutate', (
    tester,
  ) async {
    final h = await setup(tester);
    await openRenewalUi(tester, h);
    await tapRenewalUi(tester, 'scan-renewal-qr');
    final lateScan = h.lastScanned!;
    await tester.pumpWidget(const SizedBox());
    lateScan(h.qr);
    await flushRenewalUi(tester, h);
    expect(tester.takeException(), isNull);
    expect(h.paths, isEmpty);
    expect(await tester.runAsync(h.history), isEmpty);
    await tester.runAsync(h.preserved);
  });
  for (final width in [320.0, 390.0]) {
    testUi('renewal recovery wraps on a $width phone at large text scale', (
      tester,
    ) async {
      final h = await setup(tester);
      await tester.runAsync(() => h.pending(confirmation: true));
      await openRenewalUi(tester, h);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 760);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.platformDispatcher.textScaleFactorTestValue = 1.8;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pump();
      for (final key in ['resume-renewal', 'scan-renewal-qr']) {
        await tester.ensureVisible(find.byKey(ValueKey(key)));
        final bounds = tester.getRect(find.byKey(ValueKey(key)));
        expect(bounds.left, greaterThanOrEqualTo(0));
        expect(bounds.right, lessThanOrEqualTo(width));
      }
      expect(tester.takeException(), isNull);
      await tester.runAsync(h.preserved);
    });
  }
}
