import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'jera_vota.dart';
import 'votantes.dart';
import 'offline_app.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const ProviderScope(child: MiVotoApp()));
}

class ApiClient {
  ApiClient(this.baseUrl);
  final String baseUrl;
  final _client = http.Client();
  String? _cookie;
  String? _authToken;

  Map<String, String> _headers({bool jsonBody = true}) {
    final h = <String, String>{};
    if (jsonBody) h['Content-Type'] = 'application/json';
    if (_cookie != null) h['Cookie'] = _cookie!;
    if (_authToken != null) h['Authorization'] = 'Bearer ' + _authToken!;
    return h;
  }

  void _captureCookie(http.Response r) {
    final setCookie = r.headers['set-cookie'];
    if (setCookie != null && setCookie.isNotEmpty) {
      final semi = setCookie.indexOf(';');
      _cookie = semi == -1 ? setCookie : setCookie.substring(0, semi);
    }
  }

  Future<bool> login(String user, String pass) async {
    final r = await _client.post(
      Uri.parse('$baseUrl/api/auth/login/'),
      headers: _headers(),
      body: jsonEncode({'username': user, 'password': pass}),
    );
    _captureCookie(r);
    if (r.statusCode == 200) {
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      final token = data['token'] as String?;
      if (token != null) {
        // Guardar el token como cookie estilo Authorization para requests simples
        _cookie = null;
        // Añadiremos el token como header Authorization en siguientes requests
        _authToken = token;
      }
      return true;
    }
    return false;
  }

  Future<Map<String, dynamic>> getJson(String path) async {
    final r = await _client.get(Uri.parse('$baseUrl$path'), headers: _headers(jsonBody: false));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> postJson(String path, Map<String, dynamic> body) async {
    final r = await _client.post(
      Uri.parse('$baseUrl$path'),
      headers: _headers(),
      body: jsonEncode(body),
    );
    if (r.statusCode >= 400) {
      throw Exception('POST ' + path + ' failed: ' + r.statusCode.toString() + ' ' + r.body);
    }
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> me() async {
    return getJson('/api/me/');
  }

  Future<List<dynamic>> candidaturas() async {
    final data = await getJson('/api/candidaturas/');
    return data['candidaturas'] as List<dynamic>;
  }

  // Extensiones API para replicar Django
  Future<Map<String, dynamic>> lookups() async => await getJson('/api/lookups/');

  Future<List<dynamic>> jerarquiaNodes(String candId) async {
    final data = await getJson('/api/candidaturas/' + candId + '/jerarquia/nodos/');
    return (data['nodes'] as List?) ?? <dynamic>[];
  }

  Future<List<dynamic>> votantesList(String candId) async {
    final data = await getJson('/api/candidaturas/' + candId + '/votantes/');
    return (data['votantes'] as List?) ?? <dynamic>[];
  }

  Future<void> votanteCreate(String candId, Map<String, dynamic> payload) async {
    await postJson('/api/candidaturas/' + candId + '/votantes/', payload);
  }

  Future<void> asignarRol(String candId, {required String votanteId, required String rol, required bool esJefe}) async {
    await postJson('/api/candidaturas/' + candId + '/roles/asignar/', {
      'votante_id': votanteId,
      'rol': rol,
      'es_jefe': esJefe,
    });
  }

  Future<void> agendaCreate(String candId, Map<String, dynamic> payload) async {
    await postJson('/api/candidaturas/' + candId + '/agendas/', payload);
  }

  Future<void> eventoCreate(String candId, Map<String, dynamic> payload) async {
    await postJson('/api/candidaturas/' + candId + '/eventos/', payload);
  }
}

final apiProvider = Provider<ApiClient>((ref) {
  // API de producción
  const baseUrl = 'https://mivoto.corpofuturo.org';
  return ApiClient(baseUrl);
});

class MiVotoApp extends StatelessWidget {
  const MiVotoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MiVoto',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const OfflineInitializer(child: LoginScreen()),
    );
  }
}

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _doLogin() async {
    setState(() => _loading = true);
    final api = ref.read(apiProvider);
    try {
      final ok = await api.login(_userCtrl.text, _passCtrl.text);
      if (!mounted) return;
      if (ok) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const DashboardScreen()),
        );
      } else {
        setState(() => _error = 'Credenciales inválidas');
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Error de red: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('MiVoto - Ingresar')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(controller: _userCtrl, decoration: const InputDecoration(labelText: 'Usuario')),
            const SizedBox(height: 8),
            TextField(controller: _passCtrl, decoration: const InputDecoration(labelText: 'Contraseña'), obscureText: true),
            const SizedBox(height: 16),
            if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 8),
            FilledButton(onPressed: _loading ? null : _doLogin, child: _loading ? const CircularProgressIndicator() : const Text('Entrar')),
          ],
        ),
      ),
    );
  }
}

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.watch(apiProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Candidaturas')),
      body: FutureBuilder(
        future: api.candidaturas(),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          final items = (snap.data ?? []) as List<dynamic>;
          if (items.isEmpty) return const Center(child: Text('Sin candidaturas'));
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final c = items[i] as Map<String, dynamic>;
              return ListTile(
                title: Text('${c['nombres']} ${c['apellidos']}'),
                subtitle: Text(c['id'].toString()),
                onTap: () {
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => CandidaturaHome(candId: c['id'] as String),
                  ));
                },
              );
            },
          );
        },
      ),
    );
  }
}

class CandidaturaHome extends StatelessWidget {
  const CandidaturaHome({super.key, required this.candId});
  final String candId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('MiVoto - Candidatura')),
      body: GridView.count(
        padding: const EdgeInsets.all(16),
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        children: [
          _quickCard(context, Icons.account_tree, 'Jerarquía', () => JerarquiaScreen(candId: candId, candName: '')),
          _quickCard(context, Icons.people, 'Votantes', () => VotantesScreen(candId: candId, candName: '')),
          _quickCard(context, Icons.event, 'Agendas', () => AgendasScreen(candId: candId)),
          _quickCard(context, Icons.calendar_today, 'Eventos', () => EventosScreen(candId: candId)),
        ],
      ),
    );
  }
}

Widget _quickCard(BuildContext context, IconData icon, String title, Widget Function() screen) {
  return InkWell(
    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen())),
    child: Card(
      elevation: 2,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    ),
  );
}

class AgendasScreen extends ConsumerWidget {
  const AgendasScreen({super.key, required this.candId});
  final String candId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.watch(apiProvider);
    return FutureBuilder<Map<String, dynamic>>(
      future: api.me(),
      builder: (context, meSnap) {
        final waitingMe = meSnap.connectionState != ConnectionState.done;
        Map<String, dynamic>? me = !meSnap.hasError && meSnap.hasData ? meSnap.data : null;
        final vot = (me != null ? me['votante'] as Map<String, dynamic>? : null);
        final role = ((vot?['pertenencia']) ?? '').toString().toLowerCase();
        final bool canCreate = (vot?['es_candidato'] == true) || role == 'agendador';
        return Scaffold(
          appBar: AppBar(title: const Text('Agendas')),
          body: waitingMe
              ? const Center(child: CircularProgressIndicator())
              : FutureBuilder(
                  future: api.getJson('/api/candidaturas/$candId/agendas/'),
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snap.hasError) {
                      return Center(child: Text('Error: ${snap.error}'));
                    }
                    final data = (snap.data ?? {}) as Map<String, dynamic>;
                    final agendas = (data['agendas'] ?? []) as List<dynamic>;
                    if (agendas.isEmpty) return const Center(child: Text('Sin agendas'));
                    return ListView.builder(
                      itemCount: agendas.length,
                      itemBuilder: (_, i) {
                        final a = agendas[i] as Map<String, dynamic>;
                        return ListTile(
                          title: Text(a['nombre']?.toString() ?? ''),
                          subtitle: Text('Asistentes: ${a['asistentes']}'),
                        );
                      },
                    );
                  },
                ),
          floatingActionButton: canCreate
              ? FloatingActionButton.extended(
                  onPressed: () async {
                    await showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => AgendaForm(candId: candId),
                    );
                    // Nota: no recargamos aquí; la lista se actualizará al volver de la sheet si se navega
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Crear agenda'),
                )
              : null,
        );
      },
    );
  }
}

class EventosScreen extends ConsumerWidget {
  const EventosScreen({super.key, required this.candId});
  final String candId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.watch(apiProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Eventos')),
      body: FutureBuilder(
        future: api.getJson('/api/candidaturas/$candId/eventos/'),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          final data = (snap.data ?? {}) as Map<String, dynamic>;
          final eventos = (data['eventos'] ?? []) as List<dynamic>;
          if (eventos.isEmpty) return const Center(child: Text('Sin eventos'));
          return ListView.builder(
            itemCount: eventos.length,
            itemBuilder: (_, i) {
              final ev = eventos[i] as Map<String, dynamic>;
              return ListTile(
                title: Text(ev['nombre']?.toString() ?? ''),
                subtitle: Text('${ev['fecha']} ${ev['hora_inicio']} - ${ev['hora_final']}'),
              );
            },
          );
        },
      ),
    );
  }
}



class AgendaForm extends ConsumerStatefulWidget {
  const AgendaForm({super.key, required this.candId});
  final String candId;
  @override
  ConsumerState<AgendaForm> createState() => _AgendaFormState();
}

class _AgendaFormState extends ConsumerState<AgendaForm> {
  final _nombre = TextEditingController();
  final _cedulaEncargado = TextEditingController();
  final _direccion = TextEditingController();
  final _telefono = TextEditingController();
  DateTime? _fecha;
  TimeOfDay? _inicio;
  TimeOfDay? _fin;
  int? _ciudadId;
  int? _municipioId;
  int? _comunaId;
  bool _privado = false;
  int _capacidad = 0;
  Map<String, dynamic>? _lookups;
  bool _saving = false;

  @override
  void initState() { super.initState(); _loadLookups(); }

  Future<void> _loadLookups() async {
    final api = ref.read(apiProvider);
    final data = await api.lookups();
    setState(() => _lookups = data);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final api = ref.read(apiProvider);
      await api.agendaCreate(widget.candId, {
        'nombre': _nombre.text.trim(),
        'cedula_encargado': _cedulaEncargado.text.trim(),
        'direccion': _direccion.text.trim(),
        'telefono': _telefono.text.trim(),
        'ciudad': _ciudadId,
        'municipio': _municipioId,
        'comuna': _comunaId,
        'fecha': _fecha?.toIso8601String().split('T').first,
        'hora_inicio': _inicio != null ? _fmtTime(_inicio!) : null,
        'hora_final': _fin != null ? _fmtTime(_fin!) : null,
        'privado': _privado,
        'cantidad_personas': _capacidad,
        'requerimientos_publicidad': '',
        'requerimientos_logistica': '',
      });
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ciudades = (_lookups?['ciudades'] as List?) ?? [];
    final municipios = (_lookups?['municipios'] as List?)?.where((m) => _ciudadId == null || m['ciudad_id'] == _ciudadId).toList() ?? [];
    final comunas = (_lookups?['comunas'] as List?)?.where((c) => _municipioId == null || c['municipio_id'] == _municipioId).toList() ?? [];

    return Padding(
      padding: EdgeInsets.only(left: 16, right: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 16, top: 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: _nombre, decoration: const InputDecoration(labelText: 'Nombre de la reunión')),
            TextField(controller: _cedulaEncargado, decoration: const InputDecoration(labelText: 'Cédula encargado')),
            Row(children: [
              Expanded(child: TextField(controller: _direccion, decoration: const InputDecoration(labelText: 'Dirección'))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: _telefono, decoration: const InputDecoration(labelText: 'Teléfono'))),
            ]),
            Row(children: [
              Expanded(child: DropdownButtonFormField<int>(
                value: _ciudadId,
                items: ciudades.map<DropdownMenuItem<int>>((c) => DropdownMenuItem(value: c['id'] as int, child: Text(c['nombre'] as String))).toList(),
                onChanged: (v){ setState(() { _ciudadId = v; _municipioId = null; _comunaId = null; });},
                decoration: const InputDecoration(labelText: 'Ciudad'),
              )),
              const SizedBox(width: 8),
              Expanded(child: DropdownButtonFormField<int>(
                value: _municipioId,
                items: municipios.map<DropdownMenuItem<int>>((m) => DropdownMenuItem(value: m['id'] as int, child: Text(m['nombre'] as String))).toList(),
                onChanged: (v){ setState(() { _municipioId = v; _comunaId = null; });},
                decoration: const InputDecoration(labelText: 'Municipio'),
              )),
            ]),
            DropdownButtonFormField<int>(
              value: _comunaId,
              items: comunas.map<DropdownMenuItem<int>>((c) => DropdownMenuItem(value: c['id'] as int, child: Text(c['nombre'] as String))).toList(),
              onChanged: (v){ setState(() { _comunaId = v; });},
              decoration: const InputDecoration(labelText: 'Comuna'),
            ),
            Row(children: [
              Expanded(child: OutlinedButton.icon(
                onPressed: () async { final d = await showDatePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime(2100), initialDate: DateTime.now()); setState(()=> _fecha = d); },
                icon: const Icon(Icons.date_range), label: Text(_fecha != null ? _fecha!.toIso8601String().split('T').first : 'Fecha')
              )),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton.icon(
                onPressed: () async { final t = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 8, minute: 0)); setState(()=> _inicio = t); },
                icon: const Icon(Icons.schedule), label: Text(_inicio != null ? _fmtTime(_inicio!) : 'Inicio')
              )),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton.icon(
                onPressed: () async { final t = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 9, minute: 0)); setState(()=> _fin = t); },
                icon: const Icon(Icons.schedule), label: Text(_fin != null ? _fmtTime(_fin!) : 'Fin')
              )),
            ]),
            Row(children: [
              Expanded(child: Slider(value: _capacidad.toDouble(), min: 0, max: 500, divisions: 50, label: 'Cap: $_capacidad', onChanged: (v)=> setState(()=> _capacidad = v.toInt()))),
              Checkbox(value: _privado, onChanged: (v)=> setState(()=> _privado = v ?? false)), const Text('Privado')
            ]),
            const SizedBox(height: 8),
            FilledButton.icon(onPressed: _saving ? null : _save, icon: const Icon(Icons.save), label: const Text('Crear')),
          ],
        ),
      ),
    );
  }
}

String _fmtTime(TimeOfDay t) => '${t.hour.toString().padLeft(2,'0')}:${t.minute.toString().padLeft(2,'0')}';

