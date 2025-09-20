import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'main.dart';
import 'services/local_storage_service.dart';
import 'services/sync_service.dart';
import 'services/location_service.dart';
import 'votante_detail.dart';
import 'offline_app.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'widgets/speech_text_field.dart';
import 'widgets/export_filter_widget.dart';

class VotantesScreen extends ConsumerStatefulWidget {
  const VotantesScreen({super.key, required this.candId, required this.candName});
  final String candId;
  final String candName;
  @override
  ConsumerState<VotantesScreen> createState() => _VotantesScreenState();
}

class _VotantesScreenState extends ConsumerState<VotantesScreen> {
  List<dynamic> _votantes = [];
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _userData;

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final api = ref.read(apiProvider);
      final storage = ref.read(storageProvider);
      
      String? currentUserId;
      
      // Intentar cargar datos del usuario online
      try {
        _userData = await api.me();
        currentUserId = _userData!['id']?.toString() ?? _userData!['votante']?['id']?.toString();
        
        // Guardar el ID del usuario para uso offline
        if (currentUserId != null) {
          await storage.saveCurrentUserId(currentUserId);
        }
      } catch (e) {
        print('⚠️ No se pudo cargar usuario online, intentando offline...');
        
        // Si falla online, intentar cargar desde cache local
        currentUserId = await storage.getCurrentUserId();
        
        if (currentUserId != null) {
          // Crear userData básico desde datos locales
          _userData = {
            'id': currentUserId,
            'votante': {
              'id': currentUserId,
              'es_candidato': true, // Asumir permisos básicos en offline
              'es_jefe': true,
            }
          };
          print('✅ Usuario cargado desde cache offline: $currentUserId');
        } else {
          // Si no hay datos offline, crear userData mínimo
          _userData = {
            'votante': {
              'es_candidato': true, // Permitir funcionalidad básica en offline
              'es_jefe': true,
            }
          };
          print('⚠️ Sin datos de usuario - usando permisos básicos offline');
        }
      }
      
      // Intentar cargar votantes
      try {
        final allVotantes = await api.votantesList(widget.candId);
        
        // Si el usuario es candidato, puede ver todos
        final isCandidate = _userData!['votante']?['es_candidato'] == true;
        
        if (isCandidate) {
          _votantes = allVotantes;
          // Guardar todos los votantes en cache con jerarquía
          if (currentUserId != null) {
            await storage.cacheVotantesWithHierarchy(widget.candId, allVotantes, currentUserId);
          }
        } else {
          // Si no es candidato, solo mostrar su jerarquía
          if (currentUserId != null) {
            await storage.cacheVotantesWithHierarchy(widget.candId, allVotantes, currentUserId);
            _votantes = await storage.getVotantesHierarchy(widget.candId, currentUserId);
          } else {
            _votantes = [];
          }
        }
        
      } catch (e) {
        print('⚠️ No se pudo cargar votantes online, intentando offline...');
        
        // Si falla cargar online, usar datos locales
        if (currentUserId != null) {
          _votantes = await storage.getVotantesHierarchy(widget.candId, currentUserId);
          if (_votantes.isEmpty) {
            _error = 'No tienes votantes asignados en tu jerarquía aún. Agrega algunos votantes para empezar.';
          }
        } else {
          // Sin currentUserId, cargar todos los votantes offline disponibles
          final allOfflineVotantes = await storage.getVotantesHierarchy(widget.candId, '');
          _votantes = allOfflineVotantes;
          if (_votantes.isEmpty) {
            _error = 'No hay votantes disponibles offline. Conéctate a internet para sincronizar.';
          }
        }
      }
    } catch (e) {
      print('❌ Error general en _load: $e');
      _error = 'Error cargando datos. Verifica tu conexión.';
    } finally {
      setState(() { _loading = false; });
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _openCreate() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: VotanteForm(
          candId: widget.candId,
          canCreateCredentials: _canCreateCredentials(),
        ),
      ),
    );
    _load();
  }

  void _openAssignRole(Map<String, dynamic> v) async {
    await showDialog(context: context, builder: (_) => AssignRoleDialog(candId: widget.candId, votante: v));
    _load();
  }

  void _openDetail(Map<String, dynamic> v) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VotanteDetailScreen(
          candId: widget.candId,
          candName: widget.candName,
          votanteId: v['id'] as String,
        ),
      ),
    );
    _load();
  }

  bool _canAddVotantes() {
    if (_userData == null) return true; // En offline, permitir agregar votantes
    final votante = _userData!['votante'] as Map<String, dynamic>?;
    if (votante == null) return true; // En offline, permitir agregar votantes
    
    // Todos los votantes pueden agregar otros votantes
    return true;
  }

  bool _canCreateCredentials() {
    if (_userData == null) return true; // En offline, permitir crear credenciales
    final votante = _userData!['votante'] as Map<String, dynamic>?;
    if (votante == null) return true; // En offline, permitir crear credenciales
    
    // Solo jefes o candidatos pueden crear votantes con usuario y contraseña
    return votante['es_candidato'] == true || votante['es_jefe'] == true;
  }

  bool _canAssignRoles() {
    if (_userData == null) return true; // En offline, permitir asignar roles
    final votante = _userData!['votante'] as Map<String, dynamic>?;
    if (votante == null) return true; // En offline, permitir asignar roles
    
    // Solo candidatos pueden asignar roles
    return votante['es_candidato'] == true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Votantes - ${widget.candName}'),
        actions: [
          // Botón temporal para limpiar pendientes incorrectos
          IconButton(
            icon: const Icon(Icons.cleaning_services),
            onPressed: () async {
              final storage = ref.read(storageProvider);
              await storage.clearPendingVotantes();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Lista de pendientes limpiada'))
              );
            },
            tooltip: 'Limpiar pendientes',
          ),
          if (_userData != null)
            IconButton(
              icon: const Icon(Icons.info_outline),
              onPressed: () {
                final votante = _userData!['votante'] as Map<String, dynamic>?;
                final permisos = <String>[];
                if (votante?['es_candidato'] == true) permisos.add('Candidato');
                if (votante?['es_jefe'] == true) permisos.add('Jefe');
                
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Mis permisos'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Rol: ${votante?['pertenencia']?.toString() ?? 'Sin rol'}'),
                        Text('Permisos: ${permisos.isEmpty ? 'Votante' : permisos.join(', ')}'),
                        const SizedBox(height: 8),
                        const Text('✅ Puede agregar votantes'),
                        if (_canCreateCredentials())
                          const Text('✅ Puede crear usuarios con credenciales')
                        else
                          const Text('❌ No puede crear credenciales de acceso'),
                        if (_canAssignRoles())
                          const Text('✅ Puede asignar roles'),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cerrar'),
                      ),
                    ],
                  ),
                );
              },
              tooltip: 'Ver mis permisos',
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _error!.contains('permisos') ? Icons.security : Icons.error_outline, 
                          size: 64, 
                          color: _error!.contains('permisos') ? Colors.orange[300] : Colors.red[300]
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _error!.contains('permisos') ? 'Acceso Restringido' : 'Error',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        if (_userData != null) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.blue[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.blue[200]!),
                            ),
                            child: Column(
                              children: [
                                const Text('ℹ️ Tu información:', style: TextStyle(fontWeight: FontWeight.bold)),
                                const SizedBox(height: 8),
                                Text('Rol: ${_userData!['votante']?['pertenencia']?.toString() ?? 'Sin rol'}'),
                                Text('Es Jefe: ${_userData!['votante']?['es_jefe'] == true ? 'Sí' : 'No'}'),
                                Text('Es Candidato: ${_userData!['votante']?['es_candidato'] == true ? 'Sí' : 'No'}'),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ElevatedButton(
                              onPressed: _load,
                              child: const Text('Reintentar'),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton(
                              onPressed: _canAddVotantes() ? _openCreate : null,
                              child: const Text('Agregar Votante'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    // Widget de exportación y filtrado
                    if (_userData != null && _votantes.isNotEmpty) ...[
                      ExportFilterWidget(
                        candidaturaId: widget.candId,
                        candidaturaName: widget.candName,
                        hierarchyData: _votantes.cast<Map<String, dynamic>>(),
                        userData: _userData!,
                      ),
                    ],
                    
                    // Lista de votantes
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: _votantes.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final v = _votantes[i] as Map<String, dynamic>;
                      final currentUserId = _userData?['id']?.toString() ?? _userData?['votante']?['id']?.toString();
                      final createdBy = v['created_by']?.toString();
                      final isMyCreation = createdBy == currentUserId;
                      final hierarchyLevel = v['hierarchy_level'] ?? 0;
                      
                      // Obtener información del líder
                      String leaderInfo = '';
                      final lideres = v['lideres'] as List<dynamic>?;
                      if (lideres != null && lideres.isNotEmpty) {
                        // Buscar el líder en la lista de votantes
                        final leaderId = lideres.first.toString();
                        final leader = _votantes.cast<Map<String, dynamic>>().firstWhere(
                          (votante) => votante['id']?.toString() == leaderId,
                          orElse: () => <String, dynamic>{},
                        );
                        if (leader.isNotEmpty) {
                          leaderInfo = ' 👤 Líder: ${leader['nombres'] ?? ''} ${leader['apellidos'] ?? ''} (ID: ${leader['identificacion'] ?? ''})';
                        }
                      }
                      
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isMyCreation ? Colors.green[100] : Colors.blue[100],
                          child: hierarchyLevel > 0 
                              ? Text(
                                  hierarchyLevel.toString(),
                                  style: TextStyle(
                                    color: isMyCreation ? Colors.green[700] : Colors.blue[700],
                                    fontWeight: FontWeight.bold,
                                  ),
                                )
                              : Icon(
                                  isMyCreation ? Icons.person_add : Icons.person,
                                  color: isMyCreation ? Colors.green[700] : Colors.blue[700],
                                ),
                        ),
                        title: Text('${v['nombres']?.toString() ?? ''} ${v['apellidos']?.toString() ?? ''}'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('ID: ${v['identificacion']?.toString() ?? ''}  Rol: ${v['pertenencia']?.toString() ?? ''}'),
                            if (leaderInfo.isNotEmpty)
                              Text(leaderInfo, style: TextStyle(color: Colors.orange[600], fontSize: 12)),
                            if (hierarchyLevel > 0)
                              Text('🌳 Nivel $hierarchyLevel en tu árbol', style: TextStyle(color: Colors.blue[600], fontSize: 12))
                            else if (isMyCreation)
                              Text('👤 Agregado por ti', style: TextStyle(color: Colors.green[600], fontSize: 12))
                            else if (createdBy != null)
                              Text('👥 En tu jerarquía', style: TextStyle(color: Colors.blue[600], fontSize: 12))
                            else
                              Text('🏛️ Candidatura', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                          ],
                        ),
                        trailing: _canAssignRoles() 
                            ? IconButton(
                                icon: const Icon(Icons.verified_user),
                                onPressed: () => _openAssignRole(v),
                                tooltip: 'Asignar rol',
                              )
                            : null,
                        onTap: () => _openDetail(v),
                        isThreeLine: true,
                      );
                        },
                      ),
                    ),
                  ),
                ],
              ),
      floatingActionButton: _canAddVotantes()
          ? FloatingActionButton.extended(
        onPressed: _openCreate,
        icon: const Icon(Icons.person_add),
        label: const Text('Agregar votante'),
            )
          : null,
    );
  }
}

class VotanteForm extends ConsumerStatefulWidget {
  const VotanteForm({super.key, required this.candId, this.canCreateCredentials = false});
  final String candId;
  final bool canCreateCredentials;
  @override
  ConsumerState<VotanteForm> createState() => _VotanteFormState();
}

class _VotanteFormState extends ConsumerState<VotanteForm> {
  final _identCtrl = TextEditingController();
  final _nombresCtrl = TextEditingController();
  final _apellidosCtrl = TextEditingController();
  final _celCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _direccionCtrl = TextEditingController();
  final _profesionCtrl = TextEditingController();
  final _mesaVotacionCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _grupoWhatsAppCtrl = TextEditingController(); // Campo para grupo de WhatsApp
  bool _crearCredenciales = false; // Nueva variable para el checkbox
  int? _ciudadId;
  int? _municipioId;
  int? _comunaId;
  int? _puestoVotacionId;
  String? _rol;
  String? _sexo;
  bool _esJefe = false;
  bool _saving = false;
  Map<String, dynamic>? _lookups;

  // Método para auto-llenar credenciales con la identificación
  void _autoFillCredentials() {
    if (_crearCredenciales && _identCtrl.text.trim().isNotEmpty) {
      final identificacion = _identCtrl.text.trim();
      _usernameCtrl.text = identificacion;
      _passwordCtrl.text = identificacion;
    } else if (!_crearCredenciales) {
      _usernameCtrl.clear();
      _passwordCtrl.clear();
    }
  }
  final _roles = const ['Delegado','Verificado','Publicidad','Logística','Agendador'];
  final _sexos = const ['Masculino', 'Femenino', 'Otro'];
  
  // Campos de jerarquía de liderazgo
  String? _nivelJefe;
  int? _jefeCiudadId;
  int? _jefeMunicipioId;
  int? _jefeComunaId;
  int? _jefePuestoVotacionId;
  final _nivelesJefe = const [
    {'value': 'departamental', 'label': 'Departamental'},
    {'value': 'municipal', 'label': 'Municipal'},
    {'value': 'comuna', 'label': 'Comuna'},
    {'value': 'puesto_votacion', 'label': 'Puesto de Votación'},
  ];

  @override
  void initState() {
    super.initState();
    _loadLookups();
    
    // Agregar listener al campo de identificación para auto-llenar credenciales
    _identCtrl.addListener(_autoFillCredentials);
  }

  Future<void> _loadLookups() async {
    if (!mounted) return;
    
    try {
      // Intentar cargar desde API
    final api = ref.read(apiProvider);
    final data = await api.lookups();
      if (mounted) {
    setState(() { _lookups = data; });
      }
    } catch (e) {
      if (!mounted) return;
      
      // Si falla, cargar datos offline
      final storage = ref.read(storageProvider);
      final offlineData = await storage.getLookupsData();
      if (offlineData != null && mounted) {
        setState(() { _lookups = offlineData; });
      } else {
        // Si no hay datos offline, mostrar error
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No hay datos de localidad disponibles offline'))
          );
        }
      }
    }
  }

  Future<void> _saveOffline(Map<String, dynamic> payload, String? currentUserId, LocalStorageService storage) async {
    // Generar ID temporal para el votante offline
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final offlinePayload = {...payload, 'id': tempId, 'cand_id': widget.candId};
    
    print('💾 Guardando votante offline con ID: $tempId');
    
    // Agregar a la cola de sincronización
    final sync = ref.read(syncProvider);
    await sync.queueVotante(offlinePayload);
    print('✅ Votante agregado a cola de sincronización');
    
    if (!mounted) return;
    Navigator.of(context).pop();
    
    // Agregar inmediatamente a la jerarquía local con ID temporal
    if (currentUserId != null) {
      try {
        await storage.addVotanteToHierarchyWithCandId(offlinePayload, currentUserId, widget.candId);
        print('✅ Votante agregado a jerarquía local offline');
      } catch (e) {
        print('❌ Error agregando a jerarquía local: $e');
      }
    }
    
    // Mostrar modal de bienvenida
    _showWelcomeModal(offlinePayload);
    
    // Mostrar mensaje de offline
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Guardado offline - Se sincronizará automáticamente cuando haya internet'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 3),
      )
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    
    // Obtener ID del usuario actual para la jerarquía
    final storage = ref.read(storageProvider);
    String? currentUserId = await storage.getCurrentUserId();
    
    // Si no hay currentUserId guardado, intentar obtenerlo desde la API
    if (currentUserId == null) {
      try {
        final api = ref.read(apiProvider);
        final userData = await api.me();
        currentUserId = userData['id']?.toString() ?? userData['votante']?['id']?.toString();
        // Guardarlo para futuras operaciones offline
        if (currentUserId != null) {
          await storage.saveCurrentUserId(currentUserId);
        }
      } catch (e) {
        print('⚠️ No se pudo obtener userData online: $e');
        // Continuar sin currentUserId específico
      }
    }
    
    // En modo offline, generar un ID temporal si no hay currentUserId
    if (currentUserId == null) {
      currentUserId = 'temp_user_${DateTime.now().millisecondsSinceEpoch}';
      await storage.saveCurrentUserId(currentUserId);
      print('⚠️ Generando ID temporal para usuario offline: $currentUserId');
    }
    
    final payload = {
      'identificacion': _identCtrl.text.trim(),
      'nombres': _nombresCtrl.text.trim(),
      'apellidos': _apellidosCtrl.text.trim(),
      'numero_celular': _celCtrl.text.trim(),
      'email': _emailCtrl.text.trim(),
      'direccion': _direccionCtrl.text.trim(),
      'profesion': _profesionCtrl.text.trim(),
      'mesa_votacion': _mesaVotacionCtrl.text.trim(),
      'sexo': _sexo,
      'ciudad_id': _ciudadId,
      'municipio_id': _municipioId,
      'comuna_id': _comunaId,
      'puesto_votacion_id': _puestoVotacionId,
      // Opcionales para candidato
      'pertenencia': _rol,
      'es_jefe': _esJefe,
      'username': (widget.canCreateCredentials && _crearCredenciales) ? _usernameCtrl.text.trim() : '',
      'password': (widget.canCreateCredentials && _crearCredenciales) ? _passwordCtrl.text : '',
      // Campos de jerarquía de liderazgo
      'nivel_jefe': _nivelJefe,
      'jefe_ciudad_id': _jefeCiudadId,
      'jefe_municipio_id': _jefeMunicipioId,
      'jefe_comuna_id': _jefeComunaId,
      'jefe_puesto_votacion_id': _jefePuestoVotacionId,
      // Campo para jerarquía: establecer liderazgo
      'lideres': currentUserId != null ? [currentUserId] : [],
    };
    
    // Capturar ubicación si es posible
    final location = await LocationService.getCurrentLocation();
    if (location != null) {
      payload['ubicacion'] = location;
      print('📍 Ubicación capturada: $location');
    }
    
    try {
      // SIEMPRE intentar crear online primero, pero con fallback automático a offline
      try {
        print('🌐 Intentando crear votante online...');
        final api = ref.read(apiProvider);
        final result = await api.votanteCreate(widget.candId, payload);
        
        print('✅ Votante creado online exitosamente: ${result['nombres']} ${result['apellidos']}');
        
        if (!mounted) return;
        Navigator.of(context).pop();
        
        // Agregar inmediatamente a la jerarquía local con el resultado del servidor
        if (currentUserId != null) {
          await storage.addVotanteToHierarchyWithCandId(result, currentUserId, widget.candId);
        }
        
        // Mostrar modal de bienvenida con datos del servidor
        _showWelcomeModal(result);
        
        // Mostrar mensaje de éxito
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Votante creado exitosamente'))
        );
        
        print('✅ Votante creado online - NO se agrega a pendientes');
        
      } catch (e) {
        print('❌ Error creando online: $e');
        print('🔄 FALLBACK AUTOMÁTICO - Guardando offline');
        
        // FALLBACK AUTOMÁTICO: Guardar offline SIEMPRE que falle online
        await _saveOffline(payload, currentUserId, storage);
      }
    } catch (e) {
      print('❌ Error general: $e');
      print('🔄 Fallback final - guardando offline por error general');
      
      // Fallback final: usar el método centralizado
      await _saveOffline(payload, currentUserId, storage);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showWelcomeModal(Map<String, dynamic> votanteData) {
    final nombre = '${votanteData['nombres']?.toString() ?? ''} ${votanteData['apellidos']?.toString() ?? ''}';
    final celular = votanteData['numero_celular']?.toString();
    final username = votanteData['username']?.toString();
    final password = votanteData['password']?.toString();
    final hasCredentials = username != null && username.isNotEmpty;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.celebration, color: Colors.green[600], size: 28),
            const SizedBox(width: 8),
            const Expanded(child: Text('¡Votante Agregado!')),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '¡Bienvenido/a $nombre!',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text('El votante ha sido agregado exitosamente a la candidatura.'),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        '👥 Este votante estará en tu jerarquía y podrá ver los votantes que agregue.',
                        style: TextStyle(fontSize: 12, color: Colors.blue),
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Información del votante
              _buildInfoSection('📋 Información', [
                _buildInfoRow('Nombre completo', nombre),
                _buildInfoRow('Identificación', votanteData['identificacion']?.toString()),
                if (celular != null && celular.isNotEmpty)
                  _buildInfoRow('Celular', celular),
              ]),
              
              const SizedBox(height: 12),
              
              // Credenciales si las tiene
              if (hasCredentials) ...[
                _buildInfoSection('🔐 Credenciales de Acceso', [
                  _buildInfoRow('Usuario', username!),
                  _buildInfoRow('Contraseña', password ?? '(sin contraseña)'),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Estas credenciales le permitirán acceder al sistema',
                      style: TextStyle(fontSize: 12, color: Colors.blue),
                    ),
                  ),
                ]),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Este votante no tiene credenciales de acceso al sistema',
                    style: TextStyle(fontSize: 12, color: Colors.orange),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (celular != null && celular.isNotEmpty)
            TextButton.icon(
              onPressed: () => _openWhatsApp(
                celular, 
                nombre, 
                hasCredentials ? username : null, 
                hasCredentials ? password : null,
                _grupoWhatsAppCtrl.text.trim().isNotEmpty ? _grupoWhatsAppCtrl.text.trim() : null,
              ),
              icon: Icon(Icons.message, color: Colors.green[700]),
              label: Text('Invitar por WhatsApp', style: TextStyle(color: Colors.green[700])),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: Colors.blue,
          ),
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }

  Widget _buildInfoRow(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value ?? 'No definido',
              style: TextStyle(
                color: (value == null || value.isEmpty) ? Colors.grey : Colors.black,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openWhatsApp(String phoneNumber, String nombre, String? username, String? password, String? grupoWhatsApp) async {
    print('🔍 DEBUG WhatsApp - Número original: $phoneNumber');
    
    // Limpiar el número de teléfono (solo números)
    String cleanPhone = phoneNumber.replaceAll(RegExp(r'[^\d]'), '');
    print('🔍 DEBUG WhatsApp - Número limpio: $cleanPhone');
    
    // Formatear número para WhatsApp (sin + ni espacios)
    if (cleanPhone.startsWith('57') && cleanPhone.length > 10) {
      // Ya tiene código de país
      cleanPhone = cleanPhone;
    } else if (cleanPhone.length == 10) {
      // Número colombiano sin código de país
      cleanPhone = '57$cleanPhone';
    } else if (cleanPhone.length < 10) {
      // Número muy corto, agregar código de país
      cleanPhone = '57$cleanPhone';
    }
    
    print('🔍 DEBUG WhatsApp - Número final: $cleanPhone');

    // Obtener información del usuario actual para personalizar el mensaje
    String jefeInfo = '';
    try {
      final storage = ref.read(storageProvider);
      final userData = await storage.getUserData();
      if (userData != null) {
        String jefeNombre = userData['nombre'] ?? 'Tu líder';
        String jefeCargo = '';
        if (userData['es_candidato'] == true) {
          jefeCargo = 'Candidato';
        } else if (userData['es_jefe'] == true) {
          jefeCargo = 'Jefe de equipo';
        } else {
          jefeCargo = 'Líder';
        }
        jefeInfo = '$jefeNombre ($jefeCargo)';
      }
    } catch (e) {
      print('Error obteniendo datos del usuario: $e');
    }

    // Crear mensaje de invitación personalizado
    String message = '¡Hola $nombre! 👋\n\n';
    message += '¡Bienvenido/a a nuestro equipo de campaña! 🎉\n\n';
    
    if (jefeInfo.isNotEmpty) {
      message += 'Has sido agregado/a por: *$jefeInfo*\n\n';
    }
    
    message += 'Ahora formas parte de nuestra candidatura y podrás colaborar en todas las actividades de campaña.\n\n';
    
    if (username != null && username.isNotEmpty) {
      message += '🔐 *Tus credenciales de acceso:*\n';
      message += '• Usuario: *$username*\n';
      if (password != null && password.isNotEmpty) {
        message += '• Contraseña: *$password*\n';
      }
      message += '\n📱 *Accede a la plataforma:*\n';
      message += '• *App móvil:* Descarga desde aquí:\n';
      message += 'https://drive.google.com/drive/folders/1vNEUeHJGST19OZtuFzu76_knE6XGhpCH?usp=sharing\n\n';
      message += '• *Plataforma web:* Ingresa desde:\n';
      message += 'https://mivoto.corpofuturo.org\n\n';
      message += 'Con estas credenciales podrás acceder tanto desde la app como desde la web para colaborar en las actividades de campaña.\n\n';
    }
    
    // Agregar información del grupo de WhatsApp si está disponible
    if (grupoWhatsApp != null && grupoWhatsApp.isNotEmpty) {
      message += '📱 *Únete a nuestro grupo de WhatsApp:*\n';
      message += '$grupoWhatsApp\n\n';
      message += 'En este grupo podrás mantenerte al día con todas las actividades y coordinaciones del equipo.\n\n';
    }
    
    message += '¡Gracias por ser parte de nuestro equipo! 💪\n';
    message += '¡Juntos vamos a lograr grandes cosas! 🚀';

    // Codificar el mensaje para URL
    final encodedMessage = Uri.encodeComponent(message);
    final whatsappUrl = 'https://wa.me/$cleanPhone?text=$encodedMessage';
    
    print('🔍 DEBUG WhatsApp - URL generada: $whatsappUrl');

    try {
      final uri = Uri.parse(whatsappUrl);
      print('🔍 DEBUG WhatsApp - URI parseada: $uri');
      
      // Intentar múltiples métodos de lanzamiento
      bool launched = false;
      
      // Método 1: Intentar con modo externo
      try {
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          launched = true;
          print('✅ WhatsApp abierto con modo externo');
        }
      } catch (e) {
        print('❌ Error con modo externo: $e');
      }
      
      // Método 2: Si falla, intentar con modo plataforma
      if (!launched) {
        try {
          await launchUrl(uri, mode: LaunchMode.platformDefault);
          launched = true;
          print('✅ WhatsApp abierto con modo plataforma');
        } catch (e) {
          print('❌ Error con modo plataforma: $e');
        }
      }
      
      // Método 3: Intentar URL directa de WhatsApp
      if (!launched) {
        try {
          final directUri = Uri.parse('whatsapp://send?phone=$cleanPhone&text=$encodedMessage');
          if (await canLaunchUrl(directUri)) {
            await launchUrl(directUri);
            launched = true;
            print('✅ WhatsApp abierto con URL directa');
          }
        } catch (e) {
          print('❌ Error con URL directa: $e');
        }
      }
      
      if (!launched) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('No se pudo abrir WhatsApp. Número: $cleanPhone\nURL: $whatsappUrl'),
              duration: Duration(seconds: 5),
              action: SnackBarAction(
                label: 'Copiar URL',
                onPressed: () {
                  print('URL para copiar: $whatsappUrl');
                },
              ),
            ),
          );
        }
      }
    } catch (e) {
      print('❌ Error general en WhatsApp: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al abrir WhatsApp: $e\nNúmero: $cleanPhone'),
            duration: Duration(seconds: 5),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ciudades = (_lookups?['ciudades'] as List?) ?? [];
    final municipios = (_lookups?['municipios'] as List?)?.where((m) => _ciudadId == null || m['ciudad_id'] == _ciudadId).toList() ?? [];
    final comunas = (_lookups?['comunas'] as List?)?.where((c) => _municipioId == null || c['municipio_id'] == _municipioId).toList() ?? [];
    final puestos = (_lookups?['puestos_votacion'] as List?)?.where((p) => _comunaId == null || p['comuna_id'] == _comunaId).toList() ?? [];
    final puestosVotacion = (_lookups?['puestos_votacion'] as List?)?.where((p) => _jefeComunaId == null || p['comuna_id'] == _jefeComunaId).toList() ?? [];
    
    // Para jerarquía de liderazgo
    final jefeCiudades = (_lookups?['ciudades'] as List?) ?? [];
    final jefeMunicipios = (_lookups?['municipios'] as List?)?.where((m) => _jefeCiudadId == null || m['ciudad_id'] == _jefeCiudadId).toList() ?? [];
    final jefeComunas = (_lookups?['comunas'] as List?)?.where((c) => _jefeMunicipioId == null || c['municipio_id'] == _jefeMunicipioId).toList() ?? [];
    final jefePuestos = (_lookups?['puestos_votacion'] as List?)?.where((p) => _jefeComunaId == null || p['comuna_id'] == _jefeComunaId).toList() ?? [];

    return Padding(
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SpeechTextField(controller: _identCtrl, labelText: 'Identificación', keyboardType: TextInputType.number, isNumeric: true),
            SpeechTextField(controller: _nombresCtrl, labelText: 'Nombres'),
            SpeechTextField(controller: _apellidosCtrl, labelText: 'Apellidos'),
            SpeechTextField(controller: _celCtrl, labelText: 'Celular', keyboardType: TextInputType.phone, isNumeric: true),
            SpeechTextField(controller: _emailCtrl, labelText: 'Email', keyboardType: TextInputType.emailAddress),
            SpeechTextField(controller: _direccionCtrl, labelText: 'Dirección', maxLines: 2),
            SpeechTextField(controller: _profesionCtrl, labelText: 'Profesión'),
            SpeechTextField(controller: _mesaVotacionCtrl, labelText: 'Mesa de Votación', keyboardType: TextInputType.number, isNumeric: true),
            TextFormField(
              controller: _grupoWhatsAppCtrl,
              decoration: const InputDecoration(
                labelText: 'Grupo de WhatsApp (opcional)',
                hintText: 'https://chat.whatsapp.com/...',
              ),
              keyboardType: TextInputType.url,
            ),
            DropdownButtonFormField<String>(
              value: _sexo,
              items: _sexos.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
              onChanged: (v) => setState(() => _sexo = v),
              decoration: const InputDecoration(labelText: 'Sexo'),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              value: _ciudadId,
              items: ciudades.map<DropdownMenuItem<int>>((c) => DropdownMenuItem(value: c['id'] as int, child: Text(c['nombre'] as String))).toList(),
              onChanged: (v){ setState(() { _ciudadId = v; _municipioId = null; _comunaId = null; _puestoVotacionId = null; });},
              decoration: const InputDecoration(labelText: 'Ciudad'),
            ),
            DropdownButtonFormField<int>(
              value: _municipioId,
              items: municipios.map<DropdownMenuItem<int>>((m) => DropdownMenuItem(value: m['id'] as int, child: Text(m['nombre'] as String))).toList(),
              onChanged: (v){ setState(() { _municipioId = v; _comunaId = null; _puestoVotacionId = null; });},
              decoration: const InputDecoration(labelText: 'Municipio'),
            ),
            DropdownButtonFormField<int>(
              value: _comunaId,
              items: comunas.map<DropdownMenuItem<int>>((c) => DropdownMenuItem(value: c['id'] as int, child: Text(c['nombre'] as String))).toList(),
              onChanged: (v){ setState(() { _comunaId = v; _puestoVotacionId = null; });},
              decoration: const InputDecoration(labelText: 'Comuna'),
            ),
            DropdownButtonFormField<int>(
              value: _puestoVotacionId,
              items: puestos.map<DropdownMenuItem<int>>((p) => DropdownMenuItem(value: p['id'] as int, child: Text(p['nombre'] as String))).toList(),
              onChanged: (v){ setState(() { _puestoVotacionId = v; });},
              decoration: const InputDecoration(labelText: 'Puesto de Votación'),
            ),
            const SizedBox(height: 12),
            // Rol y es_jefe (serán aplicados sólo si el usuario logueado es candidato)
            DropdownButtonFormField<String>(
              value: _rol,
              items: _roles.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
              onChanged: (v)=> setState(()=> _rol = v),
              decoration: const InputDecoration(labelText: 'Rol (opcional)'),
            ),
            Row(children: [
              Checkbox(value: _esJefe, onChanged: (v)=> setState(()=> _esJefe = v ?? false)),
              const Text('Es jefe (opcional)')
            ]),
            
            // Campos de jerarquía de liderazgo (solo si es jefe)
            if (_esJefe) ...[
              const SizedBox(height: 8),
              const Divider(),
              const Text('Jerarquía de Liderazgo', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              
              DropdownButtonFormField<String>(
                value: _nivelJefe,
                items: _nivelesJefe.map((n) => DropdownMenuItem(
                  value: n['value'] as String, 
                  child: Text(n['label'] as String)
                )).toList(),
                onChanged: (v) => setState(() {
                  _nivelJefe = v;
                  // Limpiar campos dependientes
                  _jefeCiudadId = null;
                  _jefeMunicipioId = null;
                  _jefeComunaId = null;
                  _jefePuestoVotacionId = null;
                }),
                decoration: const InputDecoration(labelText: 'Nivel de Jefe'),
              ),
              
              // Departamental: Solo ciudad
              if (_nivelJefe == 'departamental') ...[
                DropdownButtonFormField<int>(
                  value: _jefeCiudadId,
                  items: jefeCiudades.map<DropdownMenuItem<int>>((c) => 
                    DropdownMenuItem(value: c['id'] as int, child: Text(c['nombre'] as String))
                  ).toList(),
                  onChanged: (v) => setState(() => _jefeCiudadId = v),
                  decoration: const InputDecoration(labelText: 'Ciudad/Departamento'),
                ),
              ],
              
              // Municipal: Ciudad + Municipio
              if (_nivelJefe == 'municipal') ...[
                DropdownButtonFormField<int>(
                  value: _jefeCiudadId,
                  items: jefeCiudades.map<DropdownMenuItem<int>>((c) => 
                    DropdownMenuItem(value: c['id'] as int, child: Text(c['nombre'] as String))
                  ).toList(),
                  onChanged: (v) => setState(() {
                    _jefeCiudadId = v;
                    _jefeMunicipioId = null;
                  }),
                  decoration: const InputDecoration(labelText: 'Ciudad/Departamento'),
                ),
                DropdownButtonFormField<int>(
                  value: _jefeMunicipioId,
                  items: jefeMunicipios.map<DropdownMenuItem<int>>((m) => 
                    DropdownMenuItem(value: m['id'] as int, child: Text(m['nombre'] as String))
                  ).toList(),
                  onChanged: (v) => setState(() => _jefeMunicipioId = v),
                  decoration: const InputDecoration(labelText: 'Municipio'),
                ),
              ],
              
              // Comuna: Ciudad + Municipio + Comuna
              if (_nivelJefe == 'comuna') ...[
                DropdownButtonFormField<int>(
                  value: _jefeCiudadId,
                  items: jefeCiudades.map<DropdownMenuItem<int>>((c) => 
                    DropdownMenuItem(value: c['id'] as int, child: Text(c['nombre'] as String))
                  ).toList(),
                  onChanged: (v) => setState(() {
                    _jefeCiudadId = v;
                    _jefeMunicipioId = null;
                    _jefeComunaId = null;
                  }),
                  decoration: const InputDecoration(labelText: 'Ciudad/Departamento'),
                ),
                DropdownButtonFormField<int>(
                  value: _jefeMunicipioId,
                  items: jefeMunicipios.map<DropdownMenuItem<int>>((m) => 
                    DropdownMenuItem(value: m['id'] as int, child: Text(m['nombre'] as String))
                  ).toList(),
                  onChanged: (v) => setState(() {
                    _jefeMunicipioId = v;
                    _jefeComunaId = null;
                  }),
                  decoration: const InputDecoration(labelText: 'Municipio'),
                ),
                DropdownButtonFormField<int>(
                  value: _jefeComunaId,
                  items: jefeComunas.map<DropdownMenuItem<int>>((c) => 
                    DropdownMenuItem(value: c['id'] as int, child: Text(c['nombre'] as String))
                  ).toList(),
                  onChanged: (v) => setState(() => _jefeComunaId = v),
                  decoration: const InputDecoration(labelText: 'Comuna'),
                ),
              ],
              
              // Puesto de Votación: Ciudad + Municipio + Comuna + Puesto
              if (_nivelJefe == 'puesto_votacion') ...[
                DropdownButtonFormField<int>(
                  value: _jefeCiudadId,
                  items: jefeCiudades.map<DropdownMenuItem<int>>((c) => 
                    DropdownMenuItem(value: c['id'] as int, child: Text(c['nombre'] as String))
                  ).toList(),
                  onChanged: (v) => setState(() {
                    _jefeCiudadId = v;
                    _jefeMunicipioId = null;
                    _jefeComunaId = null;
                    _jefePuestoVotacionId = null;
                  }),
                  decoration: const InputDecoration(labelText: 'Ciudad/Departamento'),
                ),
                DropdownButtonFormField<int>(
                  value: _jefeMunicipioId,
                  items: jefeMunicipios.map<DropdownMenuItem<int>>((m) => 
                    DropdownMenuItem(value: m['id'] as int, child: Text(m['nombre'] as String))
                  ).toList(),
                  onChanged: (v) => setState(() {
                    _jefeMunicipioId = v;
                    _jefeComunaId = null;
                    _jefePuestoVotacionId = null;
                  }),
                  decoration: const InputDecoration(labelText: 'Municipio'),
                ),
                DropdownButtonFormField<int>(
                  value: _jefeComunaId,
                  items: jefeComunas.map<DropdownMenuItem<int>>((c) => 
                    DropdownMenuItem(value: c['id'] as int, child: Text(c['nombre'] as String))
                  ).toList(),
                  onChanged: (v) => setState(() {
                    _jefeComunaId = v;
                    _jefePuestoVotacionId = null;
                  }),
                  decoration: const InputDecoration(labelText: 'Comuna'),
                ),
                DropdownButtonFormField<int>(
                  value: _jefePuestoVotacionId,
                  items: jefePuestos.map<DropdownMenuItem<int>>((p) => 
                    DropdownMenuItem(value: p['id'] as int, child: Text(p['nombre'] as String))
                  ).toList(),
                  onChanged: (v) => setState(() => _jefePuestoVotacionId = v),
                  decoration: const InputDecoration(labelText: 'Puesto de Votación'),
                ),
              ],
              const Divider(),
            ],
            // Credenciales opcionales
            // Campos de credenciales (solo para jefes/candidatos)
            if (widget.canCreateCredentials) ...[
              const SizedBox(height: 8),
              const Divider(),
              const Text('Credenciales de Acceso', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
              const Text('Solo jefes pueden crear usuarios con acceso al sistema', style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 8),
              
              // Checkbox para crear credenciales
              CheckboxListTile(
                title: const Text('¿Crear credenciales de acceso?'),
                subtitle: const Text('Usuario y contraseña serán el número de identificación'),
                value: _crearCredenciales,
                onChanged: (bool? value) {
                  setState(() {
                    _crearCredenciales = value ?? false;
                    _autoFillCredentials(); // Auto-llenar cuando cambie el checkbox
                  });
                },
                controlAffinity: ListTileControlAffinity.leading,
              ),
              
              // Campos de credenciales (solo si está marcado el checkbox)
              if (_crearCredenciales) ...[
                const SizedBox(height: 8),
                SpeechTextField(
                  controller: _usernameCtrl, 
                  labelText: 'Usuario',
                  enabled: false, // Deshabilitado porque se auto-llena
                ),
                SpeechTextField(
                  controller: _passwordCtrl, 
                  labelText: 'Contraseña',
                  enabled: false, // Deshabilitado porque se auto-llena
                ),
              ],
            ] else ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange[200]!),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Solo jefes pueden crear usuarios con credenciales de acceso',
                        style: TextStyle(fontSize: 12, color: Colors.orange),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(onPressed: _saving ? null : _save, icon: const Icon(Icons.save), label: const Text('Guardar')),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _identCtrl.removeListener(_autoFillCredentials);
    _identCtrl.dispose();
    _nombresCtrl.dispose();
    _apellidosCtrl.dispose();
    _celCtrl.dispose();
    _emailCtrl.dispose();
    _direccionCtrl.dispose();
    _profesionCtrl.dispose();
    _mesaVotacionCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _grupoWhatsAppCtrl.dispose();
    super.dispose();
  }
}

class AssignRoleDialog extends ConsumerStatefulWidget {
  const AssignRoleDialog({super.key, required this.candId, required this.votante});
  final String candId;
  final Map<String, dynamic> votante;
  @override
  ConsumerState<AssignRoleDialog> createState() => _AssignRoleDialogState();
}

class _AssignRoleDialogState extends ConsumerState<AssignRoleDialog> {
  String? _rol;
  bool _esJefe = false;
  bool _saving = false;
  final _roles = const ['Delegado','Verificado','Publicidad','Logística','Agendador'];

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final api = ref.read(apiProvider);
      await api.asignarRol(widget.candId, votanteId: widget.votante['id'] as String, rol: _rol ?? '', esJefe: _esJefe);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Asignar rol'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            value: _rol,
            items: _roles.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
            onChanged: (v) => setState(() => _rol = v),
            decoration: const InputDecoration(labelText: 'Rol'),
          ),
          Row(children: [
            Checkbox(value: _esJefe, onChanged: (v)=> setState(()=> _esJefe = v ?? false)),
            const Text('Es jefe')
          ])
        ],
      ),
      actions: [
        TextButton(onPressed: _saving ? null : ()=> Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(onPressed: _saving ? null : _save, child: const Text('Guardar')),
      ],
    );
  }
}


