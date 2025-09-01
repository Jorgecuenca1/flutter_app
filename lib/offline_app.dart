import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'main.dart';
import 'services/local_storage_service.dart';
import 'services/sync_service.dart';
import 'package:flutter/material.dart';

final storageProvider = Provider<LocalStorageService>((ref) => LocalStorageService());
final syncProvider = Provider<SyncService>((ref) => SyncService(ref.read(apiProvider), ref.read(storageProvider)));

class OfflineInitializer extends ConsumerStatefulWidget {
  const OfflineInitializer({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<OfflineInitializer> createState() => _OfflineInitializerState();
}

class _OfflineInitializerState extends ConsumerState<OfflineInitializer> {
  @override
  void initState() {
    super.initState();
    // iniciar listener de red
    ref.read(syncProvider).startNetworkListener();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class PendingListScreen extends ConsumerStatefulWidget {
  const PendingListScreen({super.key});
  @override
  ConsumerState<PendingListScreen> createState() => _PendingListScreenState();
}

class _PendingListScreenState extends ConsumerState<PendingListScreen> {
  List<Map<String, dynamic>> _pendV = [];
  List<Map<String, dynamic>> _pendA = [];
  bool _loading = true;

  Future<void> _load() async {
    setState(() => _loading = true);
    final store = ref.read(storageProvider);
    _pendV = await store.getPendingVotantesWithDetails();
    _pendA = await store.getPendingAgendas();
    setState(() => _loading = false);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _sync() async {
    final sync = ref.read(syncProvider);
    await sync.syncAll();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pendientes offline')), 
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                children: [
                  ListTile(title: Text('Votantes pendientes (${_pendV.length})')),
                  ..._pendV.asMap().entries.map((e) => Dismissible(
                        key: ValueKey('v-${e.key}'),
                        background: Container(color: Colors.red),
                        onDismissed: (_) async {
                          await ref.read(storageProvider).removePendingVotanteAt(e.key);
                          _load();
                        },
                        child: ListTile(
                          leading: const Icon(Icons.person),
                          title: Text('${e.value['nombres'] ?? ''} ${e.value['apellidos'] ?? ''}'),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('ID: ${e.value['identificacion'] ?? ''}'),
                              if (e.value['ciudad_nombre'] != null) 
                                Text('📍 ${e.value['ciudad_nombre']}${e.value['municipio_nombre'] != null ? ', ${e.value['municipio_nombre']}' : ''}${e.value['comuna_nombre'] != null ? ', ${e.value['comuna_nombre']}' : ''}'),
                              if (e.value['pertenencia'] != null)
                                Text('👤 Rol: ${e.value['pertenencia']}'),
                            ],
                          ),
                          isThreeLine: true,
                        ),
                      )),
                  const Divider(),
                  ListTile(title: Text('Agendas pendientes (${_pendA.length})')),
                  ..._pendA.asMap().entries.map((e) => Dismissible(
                        key: ValueKey('a-${e.key}'),
                        background: Container(color: Colors.red),
                        onDismissed: (_) async {
                          await ref.read(storageProvider).removePendingAgendaAt(e.key);
                          _load();
                        },
                        child: ListTile(
                          leading: const Icon(Icons.event),
                          title: Text('${e.value['nombre'] ?? ''}'),
                          subtitle: Text('Fecha: ${e.value['fecha'] ?? ''}'),
                        ),
                      )),
                  const SizedBox(height: 80),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _sync,
        icon: const Icon(Icons.sync),
        label: const Text('Sincronizar'),
      ),
    );
  }
}


