import 'dart:convert';
import 'package:ansvk_outreach/auth/auth_service.dart';
import 'package:ansvk_outreach/auth/session_controller.dart';
import 'package:ansvk_outreach/database/app_database.dart';
import 'package:ansvk_outreach/database/outreach_repository.dart';
import 'package:ansvk_outreach/hotspots/hotspot_workspace.dart';
import 'package:ansvk_outreach/hotspots/location_service.dart';
import 'package:ansvk_outreach/sync/certificate_fingerprint_store.dart';
import 'package:ansvk_outreach/sync/dashboard_certificate_checker.dart';
import 'package:ansvk_outreach/sync/device_credential_store.dart';
import 'package:ansvk_outreach/sync/manual_sync_runner.dart';
import 'package:ansvk_outreach/sync/pairing_response.dart';
import 'package:ansvk_outreach/sync/secure_sync_transport.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'auth_test_support.dart';
import 'hotspot_test_support.dart';

class Connection implements SyncHttpsConnection {
  Connection(this.respond);
  final SyncBatchReply Function(String?) respond;
  @override
  List<int> get certificateDer => [1, 2, 3];
  @override
  Future<SyncBatchReply> request(
    Uri uri,
    String method,
    String credential,
    String? body,
  ) async => respond(body);
  @override
  void close() {}
}

void main() {
  testWidgets(
    'ordinary Sync sends without review and refreshes receipt time and pending count',
    (tester) async {
      late AppDatabase db;
      late SessionController session;
      late OutreachRepository repo;
      late Map<String, Object?> identity;
      late CertificateFingerprintStore pins;
      late DeviceCredentialStore credentials;
      await tester.runAsync(() async {
        sqfliteFfiInit();
        db = await AppDatabase.open(
          factory: databaseFactoryFfi,
          path: inMemoryDatabasePath,
        );
        session = SessionController(AuthService(db, hasher: TestHasher()));
        repo = OutreachRepository(
          db,
          currentWorkerId: () => session.currentWorkerId,
        );
        await session.signIn('synthetic', 'password1', register: true);
        identity = await repo.appIdentity();
        pins = CertificateFingerprintStore();
        await pins.write(
          await DashboardCertificateChecker.sha256Hex([1, 2, 3]),
        );
        credentials = DeviceCredentialStore.memory();
        await credentials.write('synthetic');
        await repo.saveDashboardPairing(
          'https://127.0.0.1:3443/api/v1',
          '123456',
        );
        await repo.applyDashboardPairing(
          PairingSuccess(
            requestId: 'test',
            dashboardId: 'dashboard',
            dashboardName: 'Synthetic',
            deviceId: identity['device_id'] as String,
            workerId: session.currentWorkerId!,
            deviceCredential: 'synthetic',
            pairedAt: DateTime.utc(2026),
            serverTime: DateTime.utc(2026),
          ),
        );
      });
      var uploads = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: HotspotWorkspace(
            session: session,
            location: HotspotLocationService(gateway: TestLocationGateway()),
            certificateFingerprintStore: pins,
            deviceCredentialStore: credentials,
            syncConnector: (_) async => Connection((body) {
              if (body == null) {
                return SyncBatchReply(200, {
                  'ok': true,
                  'request_id': 'test',
                  'device_id': identity['device_id'],
                  'worker_id': session.currentWorkerId,
                  'device_status': 'active',
                  'cleanup_keep_days': 7,
                  'server_time': '2026-09-27T00:00:00Z',
                  'warnings': [],
                  'last_successful_sync_at': null,
                  'last_accepted_sequence': null,
                  'last_accepted_operation_id': null,
                });
              }
              uploads++;
              final batch = jsonDecode(body);
              return SyncBatchReply(200, {
                'ok': true,
                'request_id': 'test',
                'batch_id': batch['batch_id'],
                'dashboard_received_at': '2026-09-27T00:00:00Z',
                'warnings': [],
                'retry_after_seconds': null,
                'rejected': [],
                'accepted': [
                  for (final op in batch['operations'])
                    {
                      for (final key in [
                        'operation_id',
                        'entity_type',
                        'entity_id',
                        'revision',
                        'sequence',
                      ])
                        key: op[key],
                      'duplicate': false,
                      'accepted_at': '2026-09-27T00:00:00Z',
                    },
                ],
              });
            }),
          ),
        ),
      );
      Future<void> flush() async {
        await tester.runAsync(() async {
          for (var i = 0; i < 30; i++) {
            await db.connection.rawQuery('SELECT 1');
          }
        });
        await tester.pump();
      }

      await tester.tap(find.byKey(const ValueKey('open-sync-status')));
      await flush();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('normal-sync')),
        150,
        scrollable: find
            .descendant(
              of: find.byType(ListView).last,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.byKey(const ValueKey('normal-sync')));
      for (var i = 0; i < 20; i++) {
        await flush();
        if (tester
                .widget<FilledButton>(find.byKey(const ValueKey('normal-sync')))
                .onPressed !=
            null) {
          break;
        }
      }
      expect(
        uploads,
        1,
        reason: find
            .byKey(const ValueKey('normal-sync-message'))
            .evaluate()
            .map((e) => (e.widget as Text).data)
            .join(),
      );
      expect(
        find.textContaining('Sync complete. Dashboard confirmed 1 changes.'),
        findsOneWidget,
      );
      expect(await tester.runAsync(repo.pendingOperations), isEmpty);
      expect(
        (await tester.runAsync(repo.syncStatus))!['last_successful_sync_at'],
        '2026-09-27T00:00:00.000Z',
      );
      expect(find.text('Send reviewed test batch'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
      await tester.runAsync(db.close);
    },
  );
}
