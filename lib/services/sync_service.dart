import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../main.dart';
import 'local_storage_service.dart';

class SyncService {
  SyncService(this.api, this.storage);
  final ApiClient api;
  final LocalStorageService storage;

  bool _isSyncing = false;
  bool _listenerStarted = false;

  Future<void> startNetworkListener() async {
    if (_listenerStarted) return;
    _listenerStarted = true;
    Connectivity().onConnectivityChanged.listen((status) {
      final online = status != ConnectivityResult.none;
      if (online) {
        syncAll();
      }
    });
  }

  Future<void> queueVotante(Map<String, dynamic> v) async {
    final pending = await storage.getPendingVotantes();
    final key = (v['identificacion'] ?? '').toString().trim().toLowerCase();
    final exists = pending.any((p) => (p['identificacion'] ?? '').toString().trim().toLowerCase() == key);
    if (!exists) {
      pending.add(v);
      await storage.savePendingVotantes(pending);
    }
  }

  Future<void> queueAgenda(Map<String, dynamic> a) async {
    final pending = await storage.getPendingAgendas();
    final key = ((a['nombre'] ?? '').toString().trim().toLowerCase()) + '|' + ((a['fecha'] ?? '').toString());
    final exists = pending.any((p) => (((p['nombre'] ?? '').toString().trim().toLowerCase()) + '|' + ((p['fecha'] ?? '').toString())) == key);
    if (!exists) {
      pending.add(a);
      await storage.savePendingAgendas(pending);
    }
  }

  Future<void> syncAll() async {
    if (_isSyncing) return;
    _isSyncing = true;
    try {
      await syncVotantes();
      await syncAgendas();
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> syncVotantes() async {
    final pending = await storage.getPendingVotantes();
    if (pending.isEmpty) return;
    final remaining = <Map<String, dynamic>>[];
    for (final v in pending) {
      try {
        final candId = v['cand_id'] as String;
        final body = Map<String, dynamic>.from(v)..remove('cand_id');
        await api.votanteCreate(candId, body);
      } catch (_) {
        remaining.add(v);
      }
    }
    await storage.savePendingVotantes(remaining);
  }

  Future<void> syncAgendas() async {
    final pending = await storage.getPendingAgendas();
    if (pending.isEmpty) return;
    final remaining = <Map<String, dynamic>>[];
    for (final a in pending) {
      try {
        final candId = a['cand_id'] as String;
        final body = Map<String, dynamic>.from(a)..remove('cand_id');
        await api.agendaCreate(candId, body);
      } catch (_) {
        remaining.add(a);
      }
    }
    await storage.savePendingAgendas(remaining);
  }
}








