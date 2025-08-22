import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'main.dart';

class JerarquiaScreen extends ConsumerWidget {
  const JerarquiaScreen({super.key, required this.candId, required this.candName});
  final String candId;
  final String candName;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.watch(apiProvider);
    return Scaffold(
      appBar: AppBar(title: Text('Jerarquía - $candName')),
      body: FutureBuilder(
        future: api.jerarquiaNodes(candId),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
          final nodes = (snap.data ?? []) as List<dynamic>;
          if (nodes.isEmpty) return const Center(child: Text('Sin nodos'));
          final byLevel = <int, List<Map<String, dynamic>>>{};
          for (final n in nodes) {
            final m = n as Map<String, dynamic>;
            final lvl = (m['nivel'] ?? 1) as int;
            byLevel.putIfAbsent(lvl, () => []).add(m);
          }
          final levels = byLevel.keys.toList()..sort();
          return ListView.builder(
            itemCount: levels.length,
            itemBuilder: (_, i) {
              final lvl = levels[i];
              final list = byLevel[lvl]!;
              return ExpansionTile(
                title: Text('Nivel $lvl (${list.length})'),
                children: list.map((m) => ListTile(
                  title: Text('${m['nombres']} ${m['apellidos']}'),
                  subtitle: Text('ID: ${m['identificacion']}  Rol: ${m['pertenencia'] ?? ''}  Jefe: ${m['es_jefe'] == true ? 'Sí' : 'No'}'),
                )).toList(),
              );
            },
          );
        },
      ),
    );
  }
}












