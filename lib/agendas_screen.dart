import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'offline_app.dart';
import 'main.dart';

class AgendasScreen extends HookConsumerWidget {
  const AgendasScreen({super.key, required this.candId, required this.candName});
  final String candId;
  final String candName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final agendas = useState<List<Map<String, dynamic>>>([]);
    final loading = useState(true);
    final error = useState<String?>(null);
    final userData = useState<Map<String, dynamic>?>(null);

    Future<void> loadData() async {
      try {
        loading.value = true;
        error.value = null;
        
        final api = ref.read(apiProvider);
        final storage = ref.read(storageProvider);
        
        // Cargar datos del usuario
        try {
          // Intentar desde API primero
          final meData = await api.me();
          userData.value = meData['votante'] ?? meData;
        } catch (e) {
          // Fallback a storage local
          userData.value = await storage.getUserData();
        }
        
        // Cargar agendas según permisos
        final agendasData = await api.getAgendas(candId);
        agendas.value = agendasData;
        
      } catch (e) {
        error.value = 'Error cargando agendas: $e';
      } finally {
        loading.value = false;
      }
    }

    useEffect(() {
      loadData();
      return null;
    }, []);

    if (loading.value) {
      return Scaffold(
        appBar: AppBar(title: Text('Agendas - $candName')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (error.value != null) {
      return Scaffold(
        appBar: AppBar(title: Text('Agendas - $candName')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error, size: 64, color: Colors.red[300]),
              const SizedBox(height: 16),
              Text(error.value!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: loadData,
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    final userRole = (userData.value?['pertenencia'] ?? '').toString().toLowerCase();
    final isJefe = userData.value?['es_jefe'] == true;
    final isCandidato = userData.value?['es_candidato'] == true;
    

    return Scaffold(
      appBar: AppBar(
        title: Text('Agendas - $candName'),
        actions: [
          // Solo candidatos y agendadores pueden crear agendas
          if (isCandidato || userRole == 'agendador')
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () => _showCreateAgenda(context, ref, candId, loadData),
            ),
        ],
      ),
      body: agendas.value.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.event_note, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('No hay agendas disponibles'),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: loadData,
              child: ListView.builder(
                itemCount: agendas.value.length,
                itemBuilder: (context, index) {
                  final agenda = agendas.value[index];
                  return _buildAgendaCard(
                    context, 
                    ref, 
                    agenda, 
                    candId, 
                    userRole, 
                    isJefe, 
                    isCandidato,
                    loadData,
                  );
                },
              ),
            ),
      // Botón flotante para crear agendas
      floatingActionButton: (isCandidato || userRole == 'agendador')
          ? FloatingActionButton.extended(
              onPressed: () => _showCreateAgenda(context, ref, candId, loadData),
              icon: const Icon(Icons.add),
              label: const Text('Nueva Agenda'),
            )
          : null,
    );
  }

  Widget _buildAgendaCard(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> agenda,
    String candId,
    String userRole,
    bool isJefe,
    bool isCandidato,
    VoidCallback onRefresh,
  ) {
    final status = agenda['status']?.toString() ?? 'not_started';
    final isPrivate = agenda['privado'] == true;
    
    Color statusColor;
    String statusText;
    IconData statusIcon;
    
    switch (status) {
      case 'in_progress':
        statusColor = Colors.green;
        statusText = 'En progreso';
        statusIcon = Icons.play_circle;
        break;
      case 'finished':
        statusColor = Colors.red;
        statusText = 'Finalizada';
        statusIcon = Icons.check_circle;
        break;
      default:
        statusColor = Colors.orange;
        statusText = 'No ha iniciado';
        statusIcon = Icons.schedule;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor: statusColor.withOpacity(0.2),
              child: Icon(statusIcon, color: statusColor),
            ),
            title: Row(
              children: [
                Expanded(child: Text(agenda['nombre'] ?? 'Sin nombre')),
                if (isPrivate)
                  const Icon(Icons.lock, size: 16, color: Colors.orange),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('📅 ${agenda['fecha'] ?? 'Sin fecha'} ${agenda['hora_inicio'] ?? ''} - ${agenda['hora_final'] ?? ''}'),
                Text('👥 Asistentes: ${agenda['asistentes_count'] ?? 0}/${agenda['cantidad_personas'] ?? 0}'),
                Text('📍 ${agenda['direccion'] ?? 'Sin dirección'}'),
                if (agenda['encargado_nombre'] != null)
                  Text('👤 Encargado: ${agenda['encargado_nombre']}'),
              ],
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: statusColor.withOpacity(0.3)),
              ),
              child: Text(
                statusText,
                style: TextStyle(
                  color: statusColor,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            onTap: () => _showAgendaDetail(context, ref, agenda, candId, userRole, isJefe, isCandidato, onRefresh),
          ),
          
          // Botones de acción según permisos
          _buildActionButtons(context, ref, agenda, candId, userRole, isJefe, isCandidato, onRefresh),
        ],
      ),
    );
  }

  Widget _buildActionButtons(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> agenda,
    String candId,
    String userRole,
    bool isJefe,
    bool isCandidato,
    VoidCallback onRefresh,
  ) {
    final agendaId = agenda['id'] as int;
    final actions = <Widget>[];

    // Solo jefes de delegado pueden asignar delegados
    if (isJefe && userRole == 'delegado') {
      actions.add(
        TextButton.icon(
          icon: const Icon(Icons.person_add, size: 16),
          label: const Text('Delegado'),
          onPressed: () => _showAsignarDelegado(context, ref, candId, agendaId, onRefresh),
        ),
      );
    }

    // Solo jefes de verificador pueden asignar verificadores
    if (isJefe && userRole == 'verificado') {
      actions.add(
        TextButton.icon(
          icon: const Icon(Icons.verified_user, size: 16),
          label: const Text('Verificador'),
          onPressed: () => _showAsignarVerificador(context, ref, candId, agendaId, onRefresh),
        ),
      );
    }

    // Verificadores pueden agregar asistentes
    if (userRole == 'verificado') {
      actions.add(
        TextButton.icon(
          icon: const Icon(Icons.group_add, size: 16),
          label: const Text('Asistentes'),
          onPressed: () => _showGestionarAsistentes(context, ref, candId, agendaId, onRefresh),
        ),
      );
    }

    if (actions.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Wrap(
        spacing: 8,
        children: actions,
      ),
    );
  }

  void _showCreateAgenda(BuildContext context, WidgetRef ref, String candId, VoidCallback onRefresh) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: AgendaForm(candId: candId),
      ),
    ).then((_) => onRefresh());
  }

  void _showAgendaDetail(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> agenda,
    String candId,
    String userRole,
    bool isJefe,
    bool isCandidato,
    VoidCallback onRefresh,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AgendaDetailScreen(agenda: agenda, candId: candId),
      ),
    ).then((_) => onRefresh());
  }

  void _showAsignarDelegado(BuildContext context, WidgetRef ref, String candId, int agendaId, VoidCallback onRefresh) {
    showDialog(
      context: context,
      builder: (context) => AsignarRolDialog(
        candId: candId,
        agendaId: agendaId,
        rol: 'Delegado',
        onAsignar: (votanteId) async {
          final api = ref.read(apiProvider);
          await api.asignarDelegado(candId, agendaId, votanteId);
        },
      ),
    ).then((_) => onRefresh());
  }

  void _showAsignarVerificador(BuildContext context, WidgetRef ref, String candId, int agendaId, VoidCallback onRefresh) {
    showDialog(
      context: context,
      builder: (context) => AsignarRolDialog(
        candId: candId,
        agendaId: agendaId,
        rol: 'Verificado',
        onAsignar: (votanteId) async {
          final api = ref.read(apiProvider);
          await api.asignarVerificador(candId, agendaId, votanteId);
        },
      ),
    ).then((_) => onRefresh());
  }

  void _showGestionarAsistentes(BuildContext context, WidgetRef ref, String candId, int agendaId, VoidCallback onRefresh) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GestionarAsistentesScreen(
          candId: candId,
          agendaId: agendaId,
        ),
      ),
    ).then((_) => onRefresh());
  }
}

// Dialog para asignar delegado o verificador
class AsignarRolDialog extends HookConsumerWidget {
  const AsignarRolDialog({
    super.key,
    required this.candId,
    required this.agendaId,
    required this.rol,
    required this.onAsignar,
  });

  final String candId;
  final int agendaId;
  final String rol;
  final Future<void> Function(String votanteId) onAsignar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final votantes = useState<List<Map<String, dynamic>>>([]);
    final loading = useState(true);
    final error = useState<String?>(null);

    useEffect(() {
      () async {
        try {
          final api = ref.read(apiProvider);
          final data = await api.getVotantesPorRol(candId, rol);
          votantes.value = data;
        } catch (e) {
          error.value = 'Error cargando $rol: $e';
        } finally {
          loading.value = false;
        }
      }();
      return null;
    }, []);

    return AlertDialog(
      title: Text('Asignar $rol'),
      content: SizedBox(
        width: double.maxFinite,
        height: 300,
        child: loading.value
            ? const Center(child: CircularProgressIndicator())
            : error.value != null
                ? Center(child: Text(error.value!))
                : votantes.value.isEmpty
                    ? Center(child: Text('No hay ${rol}s disponibles'))
                    : ListView.builder(
                        itemCount: votantes.value.length,
                        itemBuilder: (context, index) {
                          final votante = votantes.value[index];
                          return ListTile(
                            title: Text('${votante['nombres']} ${votante['apellidos']}'),
                            subtitle: Text(votante['identificacion'] ?? ''),
                            onTap: () async {
                              try {
                                await onAsignar(votante['id']);
                                if (context.mounted) {
                                  Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('$rol asignado correctamente')),
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Error: $e')),
                                  );
                                }
                              }
                            },
                          );
                        },
                      ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}

// Pantalla para gestionar asistentes (solo verificadores)
class GestionarAsistentesScreen extends HookConsumerWidget {
  const GestionarAsistentesScreen({
    super.key,
    required this.candId,
    required this.agendaId,
  });

  final String candId;
  final int agendaId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asistentes = useState<List<Map<String, dynamic>>>([]);
    final loading = useState(true);
    final error = useState<String?>(null);
    final searchController = useTextEditingController();

    Future<void> loadAsistentes() async {
      try {
        loading.value = true;
        error.value = null;
        final api = ref.read(apiProvider);
        final data = await api.getAsistentesAgenda(candId, agendaId);
        asistentes.value = data;
      } catch (e) {
        error.value = 'Error cargando asistentes: $e';
      } finally {
        loading.value = false;
      }
    }

    Future<void> agregarAsistente(String identificacion) async {
      try {
        final api = ref.read(apiProvider);
        await api.agregarAsistente(candId, agendaId, identificacion);
        searchController.clear();
        await loadAsistentes();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Asistente agregado correctamente')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')),
          );
        }
      }
    }

    useEffect(() {
      loadAsistentes();
      return null;
    }, []);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestionar Asistentes'),
      ),
      body: Column(
        children: [
          // Formulario para agregar asistente
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: searchController,
                    decoration: const InputDecoration(
                      labelText: 'Cédula del asistente',
                      hintText: 'Ingrese la cédula...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    final cedula = searchController.text.trim();
                    if (cedula.isNotEmpty) {
                      agregarAsistente(cedula);
                    }
                  },
                  child: const Text('Agregar'),
                ),
              ],
            ),
          ),
          
          const Divider(),
          
          // Lista de asistentes
          Expanded(
            child: loading.value
                ? const Center(child: CircularProgressIndicator())
                : error.value != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(error.value!),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: loadAsistentes,
                              child: const Text('Reintentar'),
                            ),
                          ],
                        ),
                      )
                    : asistentes.value.isEmpty
                        ? const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.people_outline, size: 64, color: Colors.grey),
                                SizedBox(height: 16),
                                Text('No hay asistentes registrados'),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: loadAsistentes,
                            child: ListView.builder(
                              itemCount: asistentes.value.length,
                              itemBuilder: (context, index) {
                                final asistente = asistentes.value[index];
                                return ListTile(
                                  leading: const CircleAvatar(
                                    child: Icon(Icons.person),
                                  ),
                                  title: Text('${asistente['nombres']} ${asistente['apellidos']}'),
                                  subtitle: Text(asistente['identificacion'] ?? ''),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

// Las clases AgendaForm y AgendaDetailScreen ya existen en main.dart
