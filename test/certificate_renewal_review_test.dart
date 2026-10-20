import 'dart:async';
import 'package:ansvk_outreach/sync/certificate_renewal_qr.dart';
import 'package:ansvk_outreach/sync/certificate_renewal_review.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'certificate_renewal_qr_test_support.dart';

void main() {
  late VerifiedCertificateRenewal grant;
  late DateTime now;
  setUp(() async {
    now = renewalTime;
    grant = await CertificateRenewalQrVerifier(
      clock: () => now,
    ).verify(renewalVector['qr_uri'], context: renewalContext());
  });

  Future<void> show(
    WidgetTester tester, {
    Future<CertificateRenewalContext> Function()? load,
    ValueChanged<VerifiedCertificateRenewal>? approved,
    VoidCallback? cancel,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CertificateRenewalReview(
          renewal: grant,
          clock: () => now,
          loadContext: load ?? () async => renewalContext(),
          onApproved: approved ?? (_) {},
          onCancel: cancel ?? () {},
        ),
      ),
    );
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
  }

  testWidgets('review revalidates on approval and ignores double taps', (
    tester,
  ) async {
    var approvals = 0, reads = 0;
    await show(
      tester,
      approved: (_) => approvals++,
      load: () async {
        reads++;
        return renewalContext();
      },
    );
    await tester.tap(find.text('Continue renewal'));
    await tester.tap(find.text('Continue renewal'));
    await finish(tester);
    expect(approvals, 1);
    expect(reads, 2);
    expect(find.text('Review office approval'), findsOneWidget);
    expect(find.text(grant.compactJws), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('cancel does not validate, claim or approve', (tester) async {
    var reads = 0, approvals = 0, cancels = 0;
    await show(
      tester,
      load: () async {
        reads++;
        return renewalContext();
      },
      approved: (_) => approvals++,
      cancel: () => cancels++,
    );
    await tester.tap(find.text('Cancel'));
    expect(cancels, 1);
    expect(reads, 0);
    expect(approvals, 0);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('expired review disables continuation', (tester) async {
    var approvals = 0;
    await show(tester, approved: (_) => approvals++);
    now = renewalTime.add(const Duration(seconds: 300));
    await tester.pump(const Duration(seconds: 1));
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Continue renewal'),
    );
    expect(button.onPressed, isNull);
    expect(find.text('Expired. Ask for a new renewal QR.'), findsOneWidget);
    expect(approvals, 0);
    await tester.pumpWidget(const SizedBox());
  });
  for (final changeAt in [1, 2]) {
    testWidgets('stale session/trust at read $changeAt cannot approve', (
      tester,
    ) async {
      var reads = 0, approvals = 0;
      await show(
        tester,
        approved: (_) => approvals++,
        load: () async {
          reads++;
          return renewalContext(
            binding: reads == changeAt ? 'changed' : grant.context.binding,
          );
        },
      );
      await tester.tap(find.text('Continue renewal'));
      await finish(tester);
      expect(approvals, 0);
      expect(
        find.text(const CertificateRenewalQrException('trust_changed').message),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('expiry while rereading current context cannot approve', (
    tester,
  ) async {
    var reads = 0, approvals = 0;
    await show(
      tester,
      approved: (_) => approvals++,
      load: () async {
        if (++reads == 2) now = renewalTime.add(const Duration(seconds: 300));
        return renewalContext();
      },
    );
    await tester.tap(find.text('Continue renewal'));
    await finish(tester);
    expect(approvals, 0);
    expect(
      find.text(const CertificateRenewalQrException('expired').message),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('disposal during a context read cannot approve', (tester) async {
    final pending = Completer<CertificateRenewalContext>();
    var approvals = 0;
    await show(
      tester,
      approved: (_) => approvals++,
      load: () => pending.future,
    );
    await tester.tap(find.text('Continue renewal'));
    await tester.pumpWidget(const SizedBox());
    pending.complete(renewalContext());
    await finish(tester);
    expect(approvals, 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'unexpected reader failure shows safe text without QR or details',
    (tester) async {
      await show(tester, load: () async => throw StateError(grant.compactJws));
      await tester.tap(find.text('Continue renewal'));
      await finish(tester);
      expect(
        find.text(const CertificateRenewalQrException('trust_changed').message),
        findsOneWidget,
      );
      expect(find.textContaining(grant.compactJws), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final width in [320.0, 390.0]) {
    testWidgets('phone review wraps at width $width and large text', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 700);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.8)),
            child: child!,
          ),
          home: CertificateRenewalReview(
            renewal: grant,
            clock: () => now,
            loadContext: () async => renewalContext(),
            onApproved: (_) {},
            onCancel: () {},
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(find.text('Certificate details'), 200);
      await tester.tap(find.text('Certificate details'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.scrollUntilVisible(
        find.text(grant.toCertificateSha256),
        200,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
