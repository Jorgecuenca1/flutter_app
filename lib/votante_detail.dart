import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'main.dart';

class VotanteDetailScreen extends ConsumerStatefulWidget {
  const VotanteDetailScreen({super.key, required this.candId, required this.candName, required this.votanteId});
  final String candId;
  final String candName;
  final String votanteId;
  @override
  ConsumerState<VotanteDetailScreen> createState() => _VotanteDetailScreenState();
}

class _VotanteDetailScreenState extends ConsumerState<VotanteDetailScreen> {
  Map<String, dynamic>? _votante;
  Map<String, dynamic>? _lookups;
  bool _loading = true;
  bool _editing = false;
  bool _saving = false;
  String? _error;

  // Controllers para edición
  final _identCtrl = TextEditingController();
  final _nombresCtrl = TextEditingController();
  final _apellidosCtrl = TextEditingController();
  final _celCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _direccionCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _profesionCtrl = TextEditingController();
  final _mesaCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  
  int? _ciudadId;
  int? _municipioId;
  int? _comunaId;
  int? _puestoId;
  String? _sexo;
  String? _rol;
  bool _esJefe = false;
  
  // Campos de jerarquía de liderazgo
  String? _nivelJefe;
  int? _jefeCiudadId;
  int? _jefeMunicipioId;
  int? _jefeComunaId;
  int? _jefePuestoVotacionId;
  
  final _roles = const ['Delegado','Verificado','Publicidad','Logística','Agendador'];
  final _sexos = const ['H', 'M'];
  final _nivelesJefe = const [
    {'value': 'departamental', 'label': 'Departamental'},
    {'value': 'municipal', 'label': 'Municipal'},
    {'value': 'comuna', 'label': 'Comuna'},
    {'value': 'puesto_votacion', 'label': 'Puesto de Votación'},
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final api = ref.read(apiProvider);
      final futures = await Future.wait([
        api.votanteDetail(widget.candId, widget.votanteId),
        api.lookups(),
      ]);
      _votante = futures[0] as Map<String, dynamic>;
      _lookups = futures[1] as Map<String, dynamic>;
      _populateControllers();
    } catch (e) {
      print('Error loading votante detail: $e');
      _error = '$e';
    } finally {
      setState(() { _loading = false; });
    }
  }

  void _populateControllers() {
    if (_votante == null) return;
    try {
      _identCtrl.text = (_votante!['identificacion'] ?? '').toString();
      _nombresCtrl.text = (_votante!['nombres'] ?? '').toString();
      _apellidosCtrl.text = (_votante!['apellidos'] ?? '').toString();
      _celCtrl.text = (_votante!['numero_celular'] ?? '').toString();
      _emailCtrl.text = (_votante!['email'] ?? '').toString();
      _direccionCtrl.text = (_votante!['direccion'] ?? '').toString();
      _telefonoCtrl.text = (_votante!['telefono'] ?? '').toString();
      _profesionCtrl.text = (_votante!['profesion'] ?? '').toString();
      _mesaCtrl.text = (_votante!['mesa_votacion'] ?? '').toString();
      _usernameCtrl.text = (_votante!['username'] ?? '').toString();
      
      _ciudadId = _votante!['ciudad_id'] is int ? _votante!['ciudad_id'] : null;
      _municipioId = _votante!['municipio_id'] is int ? _votante!['municipio_id'] : null;
      _comunaId = _votante!['comuna_id'] is int ? _votante!['comuna_id'] : null;
      _puestoId = _votante!['puesto_votacion_id'] is int ? _votante!['puesto_votacion_id'] : null;
      _sexo = (_votante!['sexo'] ?? 'H').toString();
      _rol = _votante!['pertenencia']?.toString();
      _esJefe = _votante!['es_jefe'] == true;
      
      // Campos de jerarquía de liderazgo
      _nivelJefe = _votante!['nivel_jefe']?.toString();
      _jefeCiudadId = _votante!['jefe_ciudad_id'] is int ? _votante!['jefe_ciudad_id'] : null;
      _jefeMunicipioId = _votante!['jefe_municipio_id'] is int ? _votante!['jefe_municipio_id'] : null;
      _jefeComunaId = _votante!['jefe_comuna_id'] is int ? _votante!['jefe_comuna_id'] : null;
      _jefePuestoVotacionId = _votante!['jefe_puesto_votacion_id'] is int ? _votante!['jefe_puesto_votacion_id'] : null;
    } catch (e) {
      print('Error populating controllers: $e');
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final payload = {
      'identificacion': _identCtrl.text.trim(),
      'nombres': _nombresCtrl.text.trim(),
      'apellidos': _apellidosCtrl.text.trim(),
      'numero_celular': _celCtrl.text.trim(),
      'email': _emailCtrl.text.trim(),
      'direccion': _direccionCtrl.text.trim(),
      'telefono': _telefonoCtrl.text.trim(),
      'profesion': _profesionCtrl.text.trim(),
      'mesa_votacion': _mesaCtrl.text.trim(),
      'ciudad_id': _ciudadId,
      'municipio_id': _municipioId,
      'comuna_id': _comunaId,
      'puesto_votacion_id': _puestoId,
      'sexo': _sexo,
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
      final api = ref.read(apiProvider);
      await api.votanteUpdate(widget.candId, widget.votanteId, payload);
      setState(() { _editing = false; });
      _load(); // Recargar datos actualizados
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Cargando...')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Error')),
        body: Center(child: Text('Error: $_error')),
      );
    }

    final ciudades = (_lookups?['ciudades'] as List?) ?? [];
    final municipios = (_lookups?['municipios'] as List?)?.where((m) => _ciudadId == null || m['ciudad_id'] == _ciudadId).toList() ?? [];
    final comunas = (_lookups?['comunas'] as List?)?.where((c) => _municipioId == null || c['municipio_id'] == _municipioId).toList() ?? [];

    return Scaffold(
      appBar: AppBar(
        title: Text('${_votante?['nombres'] ?? ''} ${_votante?['apellidos'] ?? ''}'),
        actions: [
          if (!_editing)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => setState(() => _editing = true),
            ),
          if (_editing)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                setState(() => _editing = false);
                _populateControllers(); // Restaurar valores originales
              },
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Información básica
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Información Personal', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 12),
                    _buildField('Identificación', _identCtrl),
                    _buildField('Nombres', _nombresCtrl),
                    _buildField('Apellidos', _apellidosCtrl),
                    _buildField('Celular', _celCtrl),
                    _buildField('Email', _emailCtrl),
                    _buildField('Dirección', _direccionCtrl),
                    _buildField('Teléfono', _telefonoCtrl),
                    _buildField('Profesión', _profesionCtrl),
                    _buildField('Mesa de votación', _mesaCtrl),
                    const SizedBox(height: 8),
                    _buildDropdown('Sexo', _sexo, _sexos.map((s) => DropdownMenuItem(value: s, child: Text(s == 'H' ? 'Hombre' : 'Mujer'))).toList(), (v) => setState(() => _sexo = v)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            // Ubicación
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Ubicación', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 12),
                    _buildDropdown(
                      'Ciudad',
                      _ciudadId,
                      ciudades.map<DropdownMenuItem<int>>((c) => DropdownMenuItem(value: c['id'] as int, child: Text(c['nombre'] as String))).toList(),
                      (v) => setState(() { _ciudadId = v; _municipioId = null; _comunaId = null; }),
                    ),
                    _buildDropdown(
                      'Municipio',
                      _municipioId,
                      municipios.map<DropdownMenuItem<int>>((m) => DropdownMenuItem(value: m['id'] as int, child: Text(m['nombre'] as String))).toList(),
                      (v) => setState(() { _municipioId = v; _comunaId = null; }),
                    ),
                    _buildDropdown(
                      'Comuna',
                      _comunaId,
                      comunas.map<DropdownMenuItem<int>>((c) => DropdownMenuItem(value: c['id'] as int, child: Text(c['nombre'] as String))).toList(),
                      (v) => setState(() => _comunaId = v),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            // Rol y permisos
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Rol y Permisos', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 12),
                    _buildDropdown(
                      'Rol',
                      _rol,
                      _roles.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                      (v) => setState(() => _rol = v),
                    ),
                    if (_editing)
                      Row(children: [
                        Checkbox(value: _esJefe, onChanged: (v) => setState(() => _esJefe = v ?? false)),
                        const Text('Es jefe')
                      ])
                    else
                      ListTile(
                        title: const Text('Es jefe'),
                        trailing: Text(_esJefe ? 'Sí' : 'No'),
                        contentPadding: EdgeInsets.zero,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            // Jerarquía de Liderazgo (solo si es jefe)
            if (_esJefe) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Jerarquía de Liderazgo', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 12),
                      
                      // Nivel de jefe
                      if (_editing)
                        DropdownButtonFormField<String>(
                          value: _nivelesJefe.any((n) => n['value'] == _nivelJefe) ? _nivelJefe : null,
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
                        )
                      else
                        ListTile(
                          title: const Text('Nivel de Jefe'),
                          trailing: Text(_nivelJefe != null 
                            ? (_nivelesJefe.firstWhere((n) => n['value'] == _nivelJefe, orElse: () => {'label': _nivelJefe ?? 'No definido'})['label'] as String? ?? 'No definido')
                            : 'No definido'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      
                      // Campos específicos según el nivel
                      if (_nivelJefe != null) ...[
                        const SizedBox(height: 8),
                        ..._buildJerarquiaFields(),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            
            // Credenciales de acceso
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Credenciales de Acceso', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 12),
                    _buildField('Usuario', _usernameCtrl),
                    if (_editing)
                      _buildField('Nueva contraseña', _passwordCtrl, obscureText: true),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            // Información de registro
            if (_votante?['created_at'] != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Información de Registro', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 12),
                      ListTile(
                        title: const Text('Fecha de registro'),
                        subtitle: Text(DateTime.parse(_votante?['created_at'] ?? '').toString().split('.')[0]),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: _editing
          ? FloatingActionButton.extended(
              onPressed: _saving ? null : _save,
              icon: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save),
              label: const Text('Guardar'),
            )
          : null,
    );
  }

  // Helper para validar valores de dropdown
  T? _validateDropdownValue<T>(T? value, List<DropdownMenuItem<T>> items) {
    if (value != null && !items.any((item) => item.value == value)) {
      return null;
    }
    return value;
  }

  List<Widget> _buildJerarquiaFields() {
    if (_lookups == null) return [];
    
    final jefeCiudades = (_lookups!['ciudades'] as List?) ?? [];
    final jefeMunicipios = (_lookups!['municipios'] as List?)?.where((m) => _jefeCiudadId == null || m['ciudad_id'] == _jefeCiudadId).toList() ?? [];
    final jefeComunas = (_lookups!['comunas'] as List?)?.where((c) => _jefeMunicipioId == null || c['municipio_id'] == _jefeMunicipioId).toList() ?? [];
    final jefePuestos = (_lookups!['puestos_votacion'] as List?)?.where((p) => _jefeComunaId == null || p['comuna_id'] == _jefeComunaId).toList() ?? [];
    
    List<Widget> fields = [];
    
    // Departamental: Solo ciudad
    if (_nivelJefe == 'departamental') {
      if (_editing) {
        final ciudadItems = jefeCiudades.map<DropdownMenuItem<int>>((c) => 
          DropdownMenuItem(value: c['id'] as int, child: Text(c['nombre'] as String))
        ).toList();
        
        fields.add(DropdownButtonFormField<int>(
          value: _validateDropdownValue(_jefeCiudadId, ciudadItems),
          items: ciudadItems,
          onChanged: (v) => setState(() => _jefeCiudadId = v),
          decoration: const InputDecoration(labelText: 'Ciudad/Departamento'),
        ));
      } else {
        final ciudad = jefeCiudades.firstWhere((c) => c['id'] == _jefeCiudadId, orElse: () => {'nombre': 'No definido'});
        fields.add(ListTile(
          title: const Text('Ciudad/Departamento'),
          trailing: Text(ciudad['nombre'] as String),
          contentPadding: EdgeInsets.zero,
        ));
      }
    }
    
    // Municipal: Ciudad + Municipio
    else if (_nivelJefe == 'municipal') {
      if (_editing) {
        final ciudadItems = jefeCiudades.map<DropdownMenuItem<int>>((c) => 
          DropdownMenuItem(value: c['id'] as int, child: Text(c['nombre'] as String))
        ).toList();
        final municipioItems = jefeMunicipios.map<DropdownMenuItem<int>>((m) => 
          DropdownMenuItem(value: m['id'] as int, child: Text(m['nombre'] as String))
        ).toList();
        
        fields.addAll([
          DropdownButtonFormField<int>(
            value: _validateDropdownValue(_jefeCiudadId, ciudadItems),
            items: ciudadItems,
            onChanged: (v) => setState(() {
              _jefeCiudadId = v;
              _jefeMunicipioId = null;
            }),
            decoration: const InputDecoration(labelText: 'Ciudad/Departamento'),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            value: _validateDropdownValue(_jefeMunicipioId, municipioItems),
            items: municipioItems,
            onChanged: (v) => setState(() => _jefeMunicipioId = v),
            decoration: const InputDecoration(labelText: 'Municipio'),
          ),
        ]);
      } else {
        final ciudad = jefeCiudades.firstWhere((c) => c['id'] == _jefeCiudadId, orElse: () => {'nombre': 'No definido'});
        final municipio = jefeMunicipios.firstWhere((m) => m['id'] == _jefeMunicipioId, orElse: () => {'nombre': 'No definido'});
        fields.addAll([
          ListTile(
            title: const Text('Ciudad/Departamento'),
            trailing: Text(ciudad['nombre'] as String),
            contentPadding: EdgeInsets.zero,
          ),
          ListTile(
            title: const Text('Municipio'),
            trailing: Text(municipio['nombre'] as String),
            contentPadding: EdgeInsets.zero,
          ),
        ]);
      }
    }
    
    // Comuna: Ciudad + Municipio + Comuna
    else if (_nivelJefe == 'comuna') {
      if (_editing) {
        final ciudadItems = jefeCiudades.map<DropdownMenuItem<int>>((c) => 
          DropdownMenuItem(value: c['id'] as int, child: Text(c['nombre'] as String))
        ).toList();
        final municipioItems = jefeMunicipios.map<DropdownMenuItem<int>>((m) => 
          DropdownMenuItem(value: m['id'] as int, child: Text(m['nombre'] as String))
        ).toList();
        final comunaItems = jefeComunas.map<DropdownMenuItem<int>>((c) => 
          DropdownMenuItem(value: c['id'] as int, child: Text(c['nombre'] as String))
        ).toList();
        
        fields.addAll([
          DropdownButtonFormField<int>(
            value: _validateDropdownValue(_jefeCiudadId, ciudadItems),
            items: ciudadItems,
            onChanged: (v) => setState(() {
              _jefeCiudadId = v;
              _jefeMunicipioId = null;
              _jefeComunaId = null;
            }),
            decoration: const InputDecoration(labelText: 'Ciudad/Departamento'),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            value: _validateDropdownValue(_jefeMunicipioId, municipioItems),
            items: municipioItems,
            onChanged: (v) => setState(() {
              _jefeMunicipioId = v;
              _jefeComunaId = null;
            }),
            decoration: const InputDecoration(labelText: 'Municipio'),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            value: _validateDropdownValue(_jefeComunaId, comunaItems),
            items: comunaItems,
            onChanged: (v) => setState(() => _jefeComunaId = v),
            decoration: const InputDecoration(labelText: 'Comuna'),
          ),
        ]);
      } else {
        final ciudad = jefeCiudades.firstWhere((c) => c['id'] == _jefeCiudadId, orElse: () => {'nombre': 'No definido'});
        final municipio = jefeMunicipios.firstWhere((m) => m['id'] == _jefeMunicipioId, orElse: () => {'nombre': 'No definido'});
        final comuna = jefeComunas.firstWhere((c) => c['id'] == _jefeComunaId, orElse: () => {'nombre': 'No definido'});
        fields.addAll([
          ListTile(
            title: const Text('Ciudad/Departamento'),
            trailing: Text(ciudad['nombre'] as String),
            contentPadding: EdgeInsets.zero,
          ),
          ListTile(
            title: const Text('Municipio'),
            trailing: Text(municipio['nombre'] as String),
            contentPadding: EdgeInsets.zero,
          ),
          ListTile(
            title: const Text('Comuna'),
            trailing: Text(comuna['nombre'] as String),
            contentPadding: EdgeInsets.zero,
          ),
        ]);
      }
    }
    
    // Puesto de Votación: Ciudad + Municipio + Comuna + Puesto
    else if (_nivelJefe == 'puesto_votacion') {
      if (_editing) {
        final ciudadItems = jefeCiudades.map<DropdownMenuItem<int>>((c) => 
          DropdownMenuItem(value: c['id'] as int, child: Text(c['nombre'] as String))
        ).toList();
        final municipioItems = jefeMunicipios.map<DropdownMenuItem<int>>((m) => 
          DropdownMenuItem(value: m['id'] as int, child: Text(m['nombre'] as String))
        ).toList();
        final comunaItems = jefeComunas.map<DropdownMenuItem<int>>((c) => 
          DropdownMenuItem(value: c['id'] as int, child: Text(c['nombre'] as String))
        ).toList();
        final puestoItems = jefePuestos.map<DropdownMenuItem<int>>((p) => 
          DropdownMenuItem(value: p['id'] as int, child: Text(p['nombre'] as String))
        ).toList();
        
        fields.addAll([
          DropdownButtonFormField<int>(
            value: _validateDropdownValue(_jefeCiudadId, ciudadItems),
            items: ciudadItems,
            onChanged: (v) => setState(() {
              _jefeCiudadId = v;
              _jefeMunicipioId = null;
              _jefeComunaId = null;
              _jefePuestoVotacionId = null;
            }),
            decoration: const InputDecoration(labelText: 'Ciudad/Departamento'),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            value: _validateDropdownValue(_jefeMunicipioId, municipioItems),
            items: municipioItems,
            onChanged: (v) => setState(() {
              _jefeMunicipioId = v;
              _jefeComunaId = null;
              _jefePuestoVotacionId = null;
            }),
            decoration: const InputDecoration(labelText: 'Municipio'),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            value: _validateDropdownValue(_jefeComunaId, comunaItems),
            items: comunaItems,
            onChanged: (v) => setState(() {
              _jefeComunaId = v;
              _jefePuestoVotacionId = null;
            }),
            decoration: const InputDecoration(labelText: 'Comuna'),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            value: _validateDropdownValue(_jefePuestoVotacionId, puestoItems),
            items: puestoItems,
            onChanged: (v) => setState(() => _jefePuestoVotacionId = v),
            decoration: const InputDecoration(labelText: 'Puesto de Votación'),
          ),
        ]);
      } else {
        final ciudad = jefeCiudades.firstWhere((c) => c['id'] == _jefeCiudadId, orElse: () => {'nombre': 'No definido'});
        final municipio = jefeMunicipios.firstWhere((m) => m['id'] == _jefeMunicipioId, orElse: () => {'nombre': 'No definido'});
        final comuna = jefeComunas.firstWhere((c) => c['id'] == _jefeComunaId, orElse: () => {'nombre': 'No definido'});
        final puesto = jefePuestos.firstWhere((p) => p['id'] == _jefePuestoVotacionId, orElse: () => {'nombre': 'No definido'});
        fields.addAll([
          ListTile(
            title: const Text('Ciudad/Departamento'),
            trailing: Text(ciudad['nombre'] as String),
            contentPadding: EdgeInsets.zero,
          ),
          ListTile(
            title: const Text('Municipio'),
            trailing: Text(municipio['nombre'] as String),
            contentPadding: EdgeInsets.zero,
          ),
          ListTile(
            title: const Text('Comuna'),
            trailing: Text(comuna['nombre'] as String),
            contentPadding: EdgeInsets.zero,
          ),
          ListTile(
            title: const Text('Puesto de Votación'),
            trailing: Text(puesto['nombre'] as String),
            contentPadding: EdgeInsets.zero,
          ),
        ]);
      }
    }
    
    return fields;
  }

  Widget _buildField(String label, TextEditingController controller, {bool obscureText = false}) {
    if (!_editing) {
      return ListTile(
        title: Text(label),
        subtitle: Text(controller.text.isEmpty ? 'No especificado' : controller.text),
        contentPadding: EdgeInsets.zero,
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(labelText: label),
        obscureText: obscureText,
      ),
    );
  }

  Widget _buildDropdown<T>(String label, T? value, List<DropdownMenuItem<T>> items, void Function(T?) onChanged) {
    if (!_editing) {
      String displayValue = 'No especificado';
      if (value != null) {
        final item = items.firstWhere((item) => item.value == value, orElse: () => DropdownMenuItem(value: value, child: Text('$value')));
        displayValue = (item.child as Text).data ?? '$value';
      }
      return ListTile(
        title: Text(label),
        subtitle: Text(displayValue),
        contentPadding: EdgeInsets.zero,
      );
    }
    
    // Validar que el valor actual esté en la lista de items
    T? validValue = value;
    if (value != null && !items.any((item) => item.value == value)) {
      validValue = null; // Si el valor no está en los items, usar null
    }
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DropdownButtonFormField<T>(
        value: validValue,
        items: items,
        onChanged: onChanged,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }
}
