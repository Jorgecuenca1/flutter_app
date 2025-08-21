import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'main.dart';
import 'services/local_storage_service.dart';
import 'services/sync_service.dart';
import 'votante_detail.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

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

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final api = ref.read(apiProvider);
      _votantes = await api.votantesList(widget.candId);
    } catch (e) {
      _error = '$e';
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
        child: VotanteForm(candId: widget.candId),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Votantes - ${widget.candName}')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: _votantes.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final v = _votantes[i] as Map<String, dynamic>;
                      return ListTile(
                        title: Text('${v['nombres']} ${v['apellidos']}'),
                        subtitle: Text('ID: ${v['identificacion']}  Rol: ${v['pertenencia'] ?? ''}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.verified_user),
                          onPressed: () => _openAssignRole(v),
                        ),
                        onTap: () => _openDetail(v),
                      );
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreate,
        icon: const Icon(Icons.person_add),
        label: const Text('Agregar votante'),
      ),
    );
  }
}

class VotanteForm extends ConsumerStatefulWidget {
  const VotanteForm({super.key, required this.candId});
  final String candId;
  @override
  ConsumerState<VotanteForm> createState() => _VotanteFormState();
}

class _VotanteFormState extends ConsumerState<VotanteForm> {
  final _identCtrl = TextEditingController();
  final _nombresCtrl = TextEditingController();
  final _apellidosCtrl = TextEditingController();
  final _celCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  int? _ciudadId;
  int? _municipioId;
  int? _comunaId;
  String? _rol;
  bool _esJefe = false;
  bool _saving = false;
  Map<String, dynamic>? _lookups;
  final _roles = const ['Delegado','Verificado','Publicidad','Logística','Agendador'];
  
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
  }

  Future<void> _loadLookups() async {
    final api = ref.read(apiProvider);
    final data = await api.lookups();
    setState(() { _lookups = data; });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final payload = {
      'identificacion': _identCtrl.text.trim(),
      'nombres': _nombresCtrl.text.trim(),
      'apellidos': _apellidosCtrl.text.trim(),
      'numero_celular': _celCtrl.text.trim(),
      'email': _emailCtrl.text.trim(),
      'ciudad_id': _ciudadId,
      'municipio_id': _municipioId,
      'comuna_id': _comunaId,
      // Opcionales para candidato
      'pertenencia': _rol,
      'es_jefe': _esJefe,
      'username': _usernameCtrl.text.trim(),
      'password': _passwordCtrl.text,
      // Campos de jerarquía de liderazgo
      'nivel_jefe': _nivelJefe,
      'jefe_ciudad_id': _jefeCiudadId,
      'jefe_municipio_id': _jefeMunicipioId,
      'jefe_comuna_id': _jefeComunaId,
      'jefe_puesto_votacion_id': _jefePuestoVotacionId,
    };
    try {
      final conn = await Connectivity().checkConnectivity();
      final online = conn != ConnectivityResult.none;
      if (online) {
        final api = ref.read(apiProvider);
        await api.votanteCreate(widget.candId, payload);
      } else {
        final sync = SyncService(ref.read(apiProvider), LocalStorageService());
        await sync.queueVotante({...payload, 'cand_id': widget.candId});
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      // Si error de red, guardar offline
      final sync = SyncService(ref.read(apiProvider), LocalStorageService());
      await sync.queueVotante({...payload, 'cand_id': widget.candId});
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ciudades = (_lookups?['ciudades'] as List?) ?? [];
    final municipios = (_lookups?['municipios'] as List?)?.where((m) => _ciudadId == null || m['ciudad_id'] == _ciudadId).toList() ?? [];
    final comunas = (_lookups?['comunas'] as List?)?.where((c) => _municipioId == null || c['municipio_id'] == _municipioId).toList() ?? [];
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
            TextField(controller: _identCtrl, decoration: const InputDecoration(labelText: 'Identificación')),
            TextField(controller: _nombresCtrl, decoration: const InputDecoration(labelText: 'Nombres')),
            TextField(controller: _apellidosCtrl, decoration: const InputDecoration(labelText: 'Apellidos')),
            TextField(controller: _celCtrl, decoration: const InputDecoration(labelText: 'Celular')),
            TextField(controller: _emailCtrl, decoration: const InputDecoration(labelText: 'Email')),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              value: _ciudadId,
              items: ciudades.map<DropdownMenuItem<int>>((c) => DropdownMenuItem(value: c['id'] as int, child: Text(c['nombre'] as String))).toList(),
              onChanged: (v){ setState(() { _ciudadId = v; _municipioId = null; _comunaId = null; });},
              decoration: const InputDecoration(labelText: 'Ciudad'),
            ),
            DropdownButtonFormField<int>(
              value: _municipioId,
              items: municipios.map<DropdownMenuItem<int>>((m) => DropdownMenuItem(value: m['id'] as int, child: Text(m['nombre'] as String))).toList(),
              onChanged: (v){ setState(() { _municipioId = v; _comunaId = null; });},
              decoration: const InputDecoration(labelText: 'Municipio'),
            ),
            DropdownButtonFormField<int>(
              value: _comunaId,
              items: comunas.map<DropdownMenuItem<int>>((c) => DropdownMenuItem(value: c['id'] as int, child: Text(c['nombre'] as String))).toList(),
              onChanged: (v){ setState(() { _comunaId = v; });},
              decoration: const InputDecoration(labelText: 'Comuna'),
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
            TextField(controller: _usernameCtrl, decoration: const InputDecoration(labelText: 'Usuario (opcional)')),
            TextField(controller: _passwordCtrl, decoration: const InputDecoration(labelText: 'Contraseña (opcional)'), obscureText: true),
            const SizedBox(height: 12),
            FilledButton.icon(onPressed: _saving ? null : _save, icon: const Icon(Icons.save), label: const Text('Guardar')),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
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


