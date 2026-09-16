import 'dart:async';
import 'dart:convert';
import 'package:ansvk_outreach/app.dart';
import 'package:ansvk_outreach/auth/auth_service.dart';
import 'package:ansvk_outreach/auth/session_controller.dart';
import 'package:ansvk_outreach/database/app_database.dart';
import 'package:ansvk_outreach/database/outreach_repository.dart';
import 'package:ansvk_outreach/hotspots/location_service.dart';
import 'package:ansvk_outreach/sync/certificate_fingerprint_store.dart';
import 'package:ansvk_outreach/sync/dashboard_certificate_checker.dart';
import 'package:ansvk_outreach/sync/dashboard_pairing_service.dart';
import 'package:ansvk_outreach/sync/device_credential_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'auth_test_support.dart';
import 'hotspot_test_support.dart';

void main() {
  sqfliteFfiInit();
  late AppDatabase db;
  late SessionController session;
  late TestLocationGateway gps;
  late OutreachRepository repo;
  setUp(() async {
    db = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    session = SessionController(AuthService(db, hasher: TestHasher()));
    gps = TestLocationGateway();
    repo = OutreachRepository(
      db,
      currentWorkerId: () => session.currentWorkerId,
    );
  });
  tearDown(() async {
    session.dispose();
    await db.close();
  });

  Future<void> flush(WidgetTester tester) async {
    await tester.runAsync(() async {
      // Drain serialized SQLite work and its Dart completion callbacks.
      for (var i = 0; i < 8; i++) {
        await db.connection.rawQuery('SELECT 1');
      }
    });
    await tester.pump();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.ensureVisible(finder);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(finder);
    await flush(tester);
    await tester.pump(const Duration(milliseconds: 300));
  }

  Finder visibleListScrollable() => find.descendant(
    of: find.byType(ListView).last,
    matching: find.byType(Scrollable),
  ).first;

  Future<void> start(WidgetTester tester) async {
    await tester.runAsync(
      () => session.signIn('Alice', 'password1', register: true),
    );
    await tester.pumpWidget(
      OutreachApp(
        session: session,
        hasAccounts: true,
        location: HotspotLocationService(gateway: gps),
      ),
    );
    await tap(tester, find.byKey(const ValueKey('open-hotspots')));
  }

  testWidgets(
    'create two hotspots, search, select and show saved peers/coordinates',
    (tester) async {
      await start(tester);
      expect(
        find.text('No hotspots yet. Create your first hotspot.'),
        findsOneWidget,
      );
      await tap(tester, find.byKey(const ValueKey('new-hotspot')));
      expect(find.text('Location captured'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('hotspot-name')),
        'Hotspot A',
      );
      await tester.enterText(find.byKey(const ValueKey('peer-0')), 'Peer One');
      await tap(tester, find.byKey(const ValueKey('add-peer')));
      await tester.enterText(find.byKey(const ValueKey('peer-1')), 'Peer Two');
      await tap(tester, find.byKey(const ValueKey('save-hotspot')));
      expect(find.text('Hotspot A'), findsOneWidget);
      expect(find.text('Peer One, Peer Two'), findsOneWidget);
      gps.serviceEnabled = false;
      await tap(tester, find.byKey(const ValueKey('new-hotspot')));
      expect(find.text('GPS unavailable'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('hotspot-name')),
        'Hotspot B',
      );
      await tap(tester, find.byKey(const ValueKey('save-hotspot')));
      expect(find.text('Hotspot A'), findsOneWidget);
      expect(find.text('Hotspot B'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('search-hotspots')),
        'spot a',
      );
      await flush(tester);
      expect(find.text('Hotspot A'), findsOneWidget);
      expect(find.text('Hotspot B'), findsNothing);
      await tap(tester, find.text('Hotspot A'));
      expect(find.text('Selected hotspot'), findsOneWidget);
      expect(find.text('Peer One'), findsOneWidget);
      expect(find.text('Peer Two'), findsOneWidget);
      expect(find.text('Latitude: 16.800000'), findsOneWidget);
      expect(find.text('Longitude: 96.100000'), findsOneWidget);
      final rows = await tester.runAsync(repo.hotspots);
      expect(rows, hasLength(2));
      expect(rows![1]['latitude'], isNull);
      expect(rows[1]['longitude'], isNull);
      expect(rows[1]['location_status'], 'Unavailable');
      expect(
        gps.positions,
        1,
      ); // Selection and list navigation never capture GPS.
      session.logout();
    },
  );

  testWidgets('daily summary shows local totals for the signed-in worker', (
    tester,
  ) async {
    await tester.runAsync(
      () => session.signIn('Alice', 'password1', register: true),
    );
    final first = await tester.runAsync(
      () => repo.createHotspot(name: 'Summary A'),
    );
    final second = await tester.runAsync(
      () => repo.createHotspot(name: 'Summary B'),
    );
    await tester.runAsync(() async {
      await repo.createEncounter({
        'hotspot_id': first,
        'client_code': '2026/MY/0001',
        'client_kind': 'New',
        'hiv': 'Reactive',
        'dist_3cc': 2,
        'dist_condom': 5,
        'recollect_lds': 1,
        'refer_dic': 1,
      });
      await repo.createEncounter({
        'hotspot_id': second,
        'client_code': '2026/MY/0001',
        'client_kind': 'Old',
        'hiv': 'Non reactive',
        'dist_3cc': 3,
      });
      await repo.createEncounter({
        'hotspot_id': first,
        'client_code': '2026/MY/0002',
        'syphilis': 'Reactive',
      });
    });
    await tester.pumpWidget(
      OutreachApp(
        session: session,
        hasAccounts: true,
        location: HotspotLocationService(gateway: gps),
      ),
    );
    await tap(tester, find.byKey(const ValueKey('open-daily-summary')));
    expect(find.text('Daily summary'), findsOneWidget);
    expect(find.text('Hotspots'), findsOneWidget);
    expect(find.text('Records'), findsOneWidget);
    expect(find.text('Unique people'), findsOneWidget);
    expect(find.text('DIC referrals'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('HIV tested'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('HIV tested'), findsOneWidget);
    expect(find.text('Syphilis reactive'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Condom'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Condom'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Recollection'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Recollection'), findsOneWidget);
    session.logout();
  });

  testWidgets('sync status shows pending changes without enabling upload', (
    tester,
  ) async {
    await tester.runAsync(
      () => session.signIn('Alice', 'password1', register: true),
    );
    final site = await tester.runAsync(
      () => repo.createHotspot(name: 'Sync Site'),
    );
    await tester.runAsync(
      () => repo.createEncounter({
        'hotspot_id': site,
        'client_code': '2026/MY/0077',
      }),
    );
    final certificateFingerprint = (await tester.runAsync(
      () => DashboardCertificateChecker.sha256Hex([1, 2, 3, 4]),
    ))!;
    await tester.pumpWidget(
      OutreachApp(
        session: session,
        hasAccounts: true,
        location: HotspotLocationService(gateway: gps),
        dashboardCertificateChecker: DashboardCertificateChecker(
          probe: (_, _) async => [1, 2, 3, 4],
        ),
        pairingTransport: _FakePairingTransport(),
        deviceCredentialStore: DeviceCredentialStore.memory(),
      ),
    );
    await tap(tester, find.byKey(const ValueKey('open-sync-status')));
    expect(find.text('Sync status'), findsOneWidget);
    expect(find.text('Desktop connection'), findsOneWidget);
    expect(
      find.textContaining('checking pending changes only'),
      findsOneWidget,
    );
    expect(find.text('Pending changes'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Not configured'), findsOneWidget);
    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Address'), findsOneWidget);
    expect(find.text('Paired at'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Sync readiness'),
      200,
      scrollable: visibleListScrollable(),
    );
    expect(find.text('Sync readiness'), findsOneWidget);
    expect(find.text('Dashboard address saved'), findsOneWidget);
    expect(find.text('Pairing code saved'), findsOneWidget);
    expect(find.text('Certificate fingerprint saved'), findsOneWidget);
    expect(find.text('Ready to request pairing'), findsOneWidget);
    expect(find.text('Dashboard paired'), findsOneWidget);
    expect(find.text('Ready to sync'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Retention safety'),
      200,
      scrollable: visibleListScrollable(),
    );
    expect(find.text('Retention safety'), findsOneWidget);
    expect(find.text('Keep days on phone'), findsOneWidget);
    expect(find.text('Old client records'), findsOneWidget);
    expect(find.text('Held because unsynced'), findsOneWidget);
    expect(find.text('Eligible after acknowledgement'), findsOneWidget);
    expect(find.text('Cleanup enabled'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Pending details'),
      200,
      scrollable: visibleListScrollable(),
    );
    expect(find.text('Pending details'), findsOneWidget);
    expect(find.text('Worker changes'), findsOneWidget);
    expect(find.text('Hotspot changes'), findsOneWidget);
    expect(find.text('Client record changes'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('App identity'),
      200,
      scrollable: visibleListScrollable(),
    );
    expect(find.text('ANSVK Outreach'), findsWidgets);
    await tester.scrollUntilVisible(
      find.text('View pending changes'),
      200,
      scrollable: visibleListScrollable(),
    );
    expect(find.text('View pending changes'), findsOneWidget);
    await tap(tester, find.byKey(const ValueKey('view-pending-changes')));
    expect(find.text('Pending changes'), findsOneWidget);
    expect(find.text('Create worker account'), findsOneWidget);
    expect(find.text('Create hotspot'), findsOneWidget);
    expect(find.text('Create client record'), findsOneWidget);
    await tap(tester, find.byTooltip('Back'));
    expect(find.text('Sync status'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Set pairing information'),
      200,
      scrollable: visibleListScrollable(),
    );
    expect(find.text('Set pairing information'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Sync unavailable until dashboard setup'),
      200,
      scrollable: visibleListScrollable(),
    );
    expect(find.text('Sync unavailable until dashboard setup'), findsOneWidget);
    await tap(
      tester,
      find.byKey(const ValueKey('configure-dashboard-address')),
    );
    expect(find.text('Dashboard pairing'), findsOneWidget);
    expect(find.text('Save pairing info only'), findsOneWidget);
    expect(find.text('Check certificate'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('dashboard-address')),
      'http://192.168.1.50:3443/api/v1',
    );
    await tester.enterText(
      find.byKey(const ValueKey('dashboard-pairing-code')),
      '123456',
    );
    await tester.enterText(
      find.byKey(const ValueKey('dashboard-certificate-fingerprint')),
      certificateFingerprint,
    );
    await tap(tester, find.byKey(const ValueKey('save-dashboard-address')));
    expect(
      find.text('Enter the HTTPS device API address ending with /api/v1.'),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('dashboard-address')),
      'https://192.168.1.50:3443/api/v1',
    );
    await tester.enterText(
      find.byKey(const ValueKey('dashboard-pairing-code')),
      '12345',
    );
    await tap(tester, find.byKey(const ValueKey('save-dashboard-address')));
    expect(
      find.text('Enter the exact 6-digit pairing code from the dashboard.'),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('dashboard-pairing-code')),
      '012345',
    );
    await tester.enterText(
      find.byKey(const ValueKey('dashboard-certificate-fingerprint')),
      'not-a-fingerprint',
    );
    await tap(tester, find.byKey(const ValueKey('save-dashboard-address')));
    expect(
      find.text('Enter the full SHA-256 certificate fingerprint.'),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('dashboard-certificate-fingerprint')),
      certificateFingerprint,
    );
    await tap(tester, find.byKey(const ValueKey('save-dashboard-address')));
    for (var i = 0; i < 10 && find.text('Sync status').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      await flush(tester);
    }
    await tester.pumpAndSettle();
    expect(find.text('Sync status'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('https://192.168.1.50:3443/api/v1'),
      -200,
      scrollable: visibleListScrollable(),
    );
    expect(find.text('https://192.168.1.50:3443/api/v1'), findsOneWidget);
    expect(
      find.text(CertificateFingerprintStore.hint(certificateFingerprint)),
      findsOneWidget,
    );
    expect(find.text('Not configured'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Dashboard address saved'),
      200,
      scrollable: visibleListScrollable(),
    );
    expect(find.text('Dashboard address saved'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Ready to request pairing'),
      200,
      scrollable: visibleListScrollable(),
    );
    expect(find.text('Ready to request pairing'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Set pairing information'),
      200,
      scrollable: visibleListScrollable(),
    );
    await tap(
      tester,
      find.byKey(const ValueKey('configure-dashboard-address')),
    );
    expect(find.text('Clear saved pairing'), findsOneWidget);
    expect(find.text('Pair with dashboard'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('dashboard-pairing-code')),
      '012345',
    );
    await tap(tester, find.byKey(const ValueKey('pair-dashboard')));
    for (var i = 0; i < 10 && find.text('Sync status').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      await flush(tester);
    }
    await tester.pumpAndSettle();
    expect(find.text('Sync status'), findsOneWidget);
    expect(find.text('Paired'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Dashboard paired'),
      200,
      scrollable: visibleListScrollable(),
    );
    expect(find.text('Dashboard paired'), findsOneWidget);
    expect(find.text('Ready to sync'), findsOneWidget);
    expect(find.text('No'), findsWidgets);
    await tester.scrollUntilVisible(
      find.text('Set pairing information'),
      200,
      scrollable: visibleListScrollable(),
    );
    await tap(
      tester,
      find.byKey(const ValueKey('configure-dashboard-address')),
    );
    await tap(tester, find.byKey(const ValueKey('clear-dashboard-address')));
    expect(find.text('Sync status'), findsOneWidget);
    expect(find.text('https://192.168.1.50:3443/api/v1'), findsNothing);
    expect(
      find.text(CertificateFingerprintStore.hint(certificateFingerprint)),
      findsNothing,
    );
    session.logout();
  });

  testWidgets('today records list opens a read-only detail page', (
    tester,
  ) async {
    await tester.runAsync(
      () => session.signIn('Alice', 'password1', register: true),
    );
    final site = await tester.runAsync(
      () => repo.createHotspot(name: 'Detail Site'),
    );
    await tester.runAsync(
      () => repo.createEncounter({
        'hotspot_id': site,
        'client_code': '2026/MY/0042',
        'client_kind': 'New',
        'hiv': 'Reactive',
        'hcv': 'Non reactive',
        'dist_3cc': 2,
        'dist_condom': 5,
        'recollect_lds': 1,
        'refer_dic': 1,
        'remark': 'Needs follow up',
      }),
    );
    await tester.pumpWidget(
      OutreachApp(
        session: session,
        hasAccounts: true,
        location: HotspotLocationService(gateway: gps),
      ),
    );
    await tap(tester, find.byKey(const ValueKey('open-today-records')));
    expect(find.text("Today's records"), findsOneWidget);
    expect(find.text('2026/MY/0042'), findsOneWidget);
    expect(find.textContaining('Detail Site'), findsOneWidget);
    expect(find.textContaining('Tested HIV, HCV'), findsOneWidget);
    await tap(tester, find.text('2026/MY/0042'));
    expect(find.text('Record detail'), findsOneWidget);
    expect(find.text('Client'), findsOneWidget);
    expect(find.text('Testing'), findsOneWidget);
    expect(find.text('Reactive'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Needs follow up'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Needs follow up'), findsOneWidget);
    session.logout();
  });

  testWidgets('record detail soft deletes after confirmation', (tester) async {
    await tester.runAsync(
      () => session.signIn('Alice', 'password1', register: true),
    );
    final site = await tester.runAsync(
      () => repo.createHotspot(name: 'Delete Site'),
    );
    final id = await tester.runAsync(
      () => repo.createEncounter({
        'hotspot_id': site,
        'client_code': '2026/MY/0099',
        'hiv': 'Reactive',
      }),
    );
    await tester.pumpWidget(
      OutreachApp(
        session: session,
        hasAccounts: true,
        location: HotspotLocationService(gateway: gps),
      ),
    );
    await tap(tester, find.byKey(const ValueKey('open-today-records')));
    await tap(tester, find.text('2026/MY/0099'));
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('delete-record')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tap(tester, find.byKey(const ValueKey('delete-record')));
    expect(find.text('Delete record?'), findsOneWidget);
    await tap(tester, find.byKey(const ValueKey('confirm-delete-record')));
    expect(find.text("Today's records"), findsOneWidget);
    expect(find.text('2026/MY/0099'), findsNothing);
    expect(find.text('No client records saved today.'), findsOneWidget);
    expect(await tester.runAsync(repo.todayEncounters), isEmpty);
    expect(await tester.runAsync(() => repo.encounter(id!)), isNull);
    final operations = await tester.runAsync(repo.pendingOperations);
    expect(operations!.where((row) => row['action'] == 'delete'), hasLength(1));
    session.logout();
  });

  testWidgets('record detail edits saved fields and returns to today list', (
    tester,
  ) async {
    await tester.runAsync(
      () => session.signIn('Alice', 'password1', register: true),
    );
    final site = await tester.runAsync(
      () => repo.createHotspot(name: 'Edit Site'),
    );
    final id = await tester.runAsync(
      () => repo.createEncounter({
        'hotspot_id': site,
        'client_code': '2026/MY/0088',
        'hiv': 'No',
        'dist_3cc': 1,
        'remark': 'Before edit',
      }),
    );
    await tester.pumpWidget(
      OutreachApp(
        session: session,
        hasAccounts: true,
        location: HotspotLocationService(gateway: gps),
      ),
    );
    await tap(tester, find.byKey(const ValueKey('open-today-records')));
    await tap(tester, find.text('2026/MY/0088'));
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('edit-record')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tap(tester, find.byKey(const ValueKey('edit-record')));
    expect(find.text('Edit record'), findsOneWidget);
    expect(
      find.text('Client code cannot be changed while editing.'),
      findsOneWidget,
    );
    final editScroll = find
        .descendant(
          of: find.byKey(const ValueKey('client-entry-scroll')),
          matching: find.byType(Scrollable),
        )
        .first;
    await tap(tester, find.text('Old'));
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('test-HIV')),
      200,
      scrollable: editScroll,
    );
    await tap(tester, find.byKey(const ValueKey('test-HIV')));
    await tap(tester, find.text('Reactive').last);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('quantity-dist_3cc')),
      200,
      scrollable: editScroll,
    );
    await tester.enterText(
      find.byKey(const ValueKey('quantity-dist_3cc')),
      '4',
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('remark')),
      200,
      scrollable: editScroll,
    );
    await tester.enterText(find.byKey(const ValueKey('remark')), 'After edit');
    await tap(tester, find.byKey(const ValueKey('update-record-top')));
    expect(find.text("Today's records"), findsOneWidget);
    expect(find.textContaining('Edit Site - Old - Tested HIV'), findsOneWidget);
    final record = await tester.runAsync(() => repo.encounter(id!));
    expect(record!['client_kind'], 'Old');
    expect(record['hiv'], 'Reactive');
    expect(record['dist_3cc'], 4);
    expect(record['remark'], 'After edit');
    expect(record['revision'], 2);
    final operations = await tester.runAsync(repo.pendingOperations);
    expect(operations!.where((row) => row['action'] == 'update'), hasLength(1));
    session.logout();
  });

  testWidgets(
    'draft survives lock and failed permission; other account has an empty list',
    (tester) async {
      gps.serviceEnabled = false;
      await start(tester);
      await tap(tester, find.byKey(const ValueKey('new-hotspot')));
      await tester.enterText(
        find.byKey(const ValueKey('hotspot-name')),
        'Draft A',
      );
      await tester.enterText(find.byKey(const ValueKey('peer-0')), 'Peer One');
      session.lock();
      await tester.pump();
      expect(find.text('App locked'), findsOneWidget);
      expect(find.byKey(const ValueKey('hotspot-name')), findsNothing);
      await tester.runAsync(() => session.unlock('password1'));
      await tester.pump();
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('hotspot-name')))
            .controller!
            .text,
        'Draft A',
      );
      await tap(tester, find.byKey(const ValueKey('save-hotspot')));
      expect(find.text('Draft A'), findsOneWidget);
      session.logout();
      await tester.pump();
      await tester.runAsync(
        () => session.signIn('Bob', 'password2', register: true),
      );
      await tester.pump();
      await tap(tester, find.byKey(const ValueKey('open-hotspots')));
      expect(find.text('Draft A'), findsNothing);
      expect(
        find.text('No hotspots yet. Create your first hotspot.'),
        findsOneWidget,
      );
      session.logout();
      await tester.pump();
      await tester.runAsync(() => session.signIn('Alice', 'password1'));
      await tester.pump();
      await tap(tester, find.byKey(const ValueKey('open-hotspots')));
      expect(find.text('Draft A'), findsOneWidget);
      session.logout();
    },
  );

  testWidgets(
    'skipping a pending fix saves null coordinates and ignores late results',
    (tester) async {
      gps.pending = Completer<LocationCapture>();
      await start(tester);
      await tap(tester, find.byKey(const ValueKey('new-hotspot')));
      await tester.enterText(
        find.byKey(const ValueKey('hotspot-name')),
        'Skipped',
      );
      await tap(tester, find.text('Continue without GPS'));
      gps.pending!.complete(const LocationCapture.available(1, 2));
      await tester.pump();
      expect(find.text('GPS unavailable'), findsOneWidget);
      await tap(tester, find.byKey(const ValueKey('save-hotspot')));
      final rows = await tester.runAsync(repo.hotspots);
      expect(rows!.single['latitude'], isNull);
      expect(rows.single['location_status'], 'Unavailable');
      session.logout();
    },
  );
}

class _FakePairingTransport implements PairingTransport {
  final credential = 'credential-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx';
  late Map<String, Object?> request;

  @override
  Future<PairingTransportResponse> postJson(
    Uri uri,
    String jsonBody, {
    required String expectedCertificateFingerprint,
  }) async {
    expect(uri.toString(), 'https://192.168.1.50:3443/api/v1/pairing/requests');
    expect(expectedCertificateFingerprint, isNotEmpty);
    request = jsonDecode(jsonBody) as Map<String, Object?>;
    return PairingTransportResponse(
      statusCode: 200,
      body: jsonEncode({
        'ok': true,
        'request_id': 'request-widget-1',
        'dashboard_id': 'dashboard-widget',
        'dashboard_name': 'Widget Dashboard',
        'device_id': request['device_id'],
        'worker_id': request['worker_id'],
        'device_credential': credential,
        'paired_at': '2026-09-17T01:00:00Z',
        'server_time': '2026-09-17T01:00:01Z',
      }),
    );
  }
}
