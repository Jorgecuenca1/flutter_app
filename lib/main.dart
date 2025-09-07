import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'jera_vota.dart';
import 'votantes.dart';
import 'jerarquia_localidad.dart';
import 'arbol_screen.dart';
import 'offline_app.dart';
import 'profile_screen.dart';
import 'services/local_storage_service.dart';
import 'widgets/cedula_selector_widget.dart';
import 'widgets/role_specific_selector_widget.dart';
import 'package:http/http.dart' as http;

void main() {
  // Configurar SSL para permitir certificados autofirmados o con problemas
  HttpOverrides.global = MyHttpOverrides();
  runApp(const ProviderScope(child: MiVotoApp()));
}

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  }
}

class ApiClient {
  ApiClient(this.baseUrl, [this._storage]);
  final String baseUrl;
  final _client = http.Client();
  String? _cookie;
  String? _authToken;
  final LocalStorageService? _storage;

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
        
        // Guardar sesión persistente
        if (_storage != null) {
          await _storage!.saveAuthToken(token);
          await _storage!.setLoggedIn(true);
          
          // Obtener y guardar información del usuario
          try {
            final userData = await me();
            final userId = userData['id']?.toString() ?? userData['votante']?['id']?.toString();
            if (userId != null) {
              await _storage!.saveCurrentUserId(userId);
            }
          } catch (e) {
            // Si falla obtener el usuario, no es crítico
          }
        }
      }
      return true;
    }
    return false;
  }

  Future<Map<String, dynamic>> getJson(String path) async {
    try {
    final r = await _client.get(Uri.parse('$baseUrl$path'), headers: _headers(jsonBody: false));
    if (r.statusCode >= 400) {
      throw Exception('GET ' + path + ' failed: ' + r.statusCode.toString() + ' ' + r.body);
    }
    if (r.body.startsWith('<!DOCTYPE') || r.body.startsWith('<html')) {
      throw Exception('Received HTML instead of JSON. Check authentication.');
    }
    return jsonDecode(r.body) as Map<String, dynamic>;
    } catch (e) {
      if (e.toString().contains('Failed host lookup') || 
          e.toString().contains('SocketException') ||
          e.toString().contains('HandshakeException') ||
          e.toString().contains('No address associated with hostname')) {
        throw Exception('Sin conexión a internet. Verifica tu conectividad.');
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> postJson(String path, Map<String, dynamic> body) async {
    try {
    final r = await _client.post(
      Uri.parse('$baseUrl$path'),
      headers: _headers(),
      body: jsonEncode(body),
    );
    if (r.statusCode >= 400) {
      throw Exception('POST ' + path + ' failed: ' + r.statusCode.toString() + ' ' + r.body);
    }
    if (r.body.startsWith('<!DOCTYPE') || r.body.startsWith('<html')) {
      throw Exception('Received HTML instead of JSON. Check authentication.');
    }
    return jsonDecode(r.body) as Map<String, dynamic>;
    } catch (e) {
      if (e.toString().contains('Failed host lookup') || 
          e.toString().contains('SocketException') ||
          e.toString().contains('HandshakeException') ||
          e.toString().contains('No address associated with hostname')) {
        throw Exception('Sin conexión a internet. Verifica tu conectividad.');
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> me() async {
    try {
      final data = await getJson('/api/me/');
      // Guardar en cache
      if (_storage != null) {
        await _storage!.cacheUserData(data);
      }
      return data;
    } catch (e) {
      // Si falla, intentar cargar desde cache
      if (_storage != null) {
        final cached = await _storage!.getCachedUserData();
        if (cached != null) {
          return cached;
        }
      }
      rethrow;
    }
  }

  Future<List<dynamic>> candidaturas() async {
    try {
    final data = await getJson('/api/candidaturas/');
      final candidaturas = data['candidaturas'] as List<dynamic>;
      // Guardar en cache
      if (_storage != null) {
        await _storage!.cacheCandidaturas(candidaturas);
      }
      return candidaturas;
    } catch (e) {
      // Si falla, intentar cargar desde cache
      if (_storage != null) {
        final cached = await _storage!.getCachedCandidaturas();
        if (cached.isNotEmpty) {
          return cached;
        }
      }
      rethrow;
    }
  }

  // Extensiones API para replicar Django
  Future<Map<String, dynamic>> lookups() async {
    final data = await getJson('/api/lookups/');
    
    // Guardar datos offline para uso posterior
    if (_storage != null) {
      await _storage!.saveLookupsData(data);
    }
    
    return data;
  }

  Future<List<dynamic>> jerarquiaNodes(String candId) async {
    final data = await getJson('/api/candidaturas/' + candId + '/jerarquia/nodos/');
    return (data['nodes'] as List?) ?? <dynamic>[];
  }

  Future<List<dynamic>> votantesList(String candId) async {
    final data = await getJson('/api/candidaturas/' + candId + '/votantes/');
    return (data['votantes'] as List?) ?? <dynamic>[];
  }

  // Método alternativo para jefes que solo pueden ver su jerarquía
  Future<List<dynamic>> votantesListHierarchy(String candId) async {
    try {
      // Intentar endpoint específico para jerarquía si existe
      final data = await getJson('/api/candidaturas/' + candId + '/votantes/jerarquia/');
      return (data['votantes'] as List?) ?? <dynamic>[];
    } catch (e) {
      // Si no existe el endpoint, usar el método normal
      return await votantesList(candId);
    }
  }

  Future<Map<String, dynamic>> votanteCreate(String candId, Map<String, dynamic> payload) async {
    print('📤 Enviando votante al servidor: ${payload['nombres']} ${payload['apellidos']}');
    print('📤 URL: $baseUrl/api/candidaturas/$candId/votantes/');
    print('📤 Auth token presente: ${_authToken != null}');
    
    try {
      final response = await postJson('/api/candidaturas/' + candId + '/votantes/', payload);
      print('📥 Respuesta del servidor: $response');
      return response['votante'] as Map<String, dynamic>;
    } catch (e) {
      print('❌ Error en votanteCreate: $e');
      rethrow;
    }
  }

  Future<void> asignarRol(String candId, {required String votanteId, required String rol, required bool esJefe}) async {
    await postJson('/api/candidaturas/' + candId + '/roles/asignar/', {
      'votante_id': votanteId,
      'rol': rol,
      'es_jefe': esJefe,
    });
  }

  Future<Map<String, dynamic>> votanteDetail(String candId, String votId) async {
    final data = await getJson('/api/candidaturas/' + candId + '/votantes/' + votId + '/');
    return data['votante'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> putJson(String path, Map<String, dynamic> body) async {
    final r = await _client.put(
      Uri.parse('$baseUrl$path'),
      headers: _headers(),
      body: jsonEncode(body),
    );
    if (r.statusCode >= 400) {
      throw Exception('PUT ' + path + ' failed: ' + r.statusCode.toString() + ' ' + r.body);
    }
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<void> votanteUpdate(String candId, String votId, Map<String, dynamic> payload) async {
    await putJson('/api/candidaturas/' + candId + '/votantes/' + votId + '/', payload);
  }

  Future<void> agendaCreate(String candId, Map<String, dynamic> payload) async {
    await postJson('/api/candidaturas/' + candId + '/agendas/', payload);
  }

  // Obtener votantes por rol específico
  Future<List<Map<String, dynamic>>> getVotantesPorRol(String candId, String rol) async {
    final response = await getJson('/api/candidaturas/$candId/votantes/?rol=$rol');
    return (response['votantes'] as List).cast<Map<String, dynamic>>();
  }

  // Asignar delegado a agenda
  Future<void> asignarDelegado(String candId, int agendaId, String delegadoId) async {
    await postJson('/agenda/$candId/$agendaId/delegado/', {
      'delegado': delegadoId,
    });
  }

  // Asignar verificador a agenda
  Future<void> asignarVerificador(String candId, int agendaId, String verificadorId) async {
    await postJson('/agenda/$candId/$agendaId/verificador/', {
      'verificador': verificadorId,
    });
  }

  // Obtener agendas
  Future<List<Map<String, dynamic>>> getAgendas(String candId) async {
    final response = await getJson('/api/candidaturas/$candId/agendas/');
    return (response['agendas'] as List).cast<Map<String, dynamic>>();
  }

  Future<void> eventoCreate(String candId, Map<String, dynamic> payload) async {
    await postJson('/api/candidaturas/' + candId + '/eventos/', payload);
  }

  // Jerarquía por localidad
  Future<Map<String, dynamic>> jerarquiaLocalidad(String candidaturaId) async {
    return await getJson('/api/candidaturas/$candidaturaId/jerarquia-localidad/');
  }

  Future<Map<String, dynamic>> buscarLideresLocalidad(String candidaturaId, String busqueda) async {
    return await getJson('/api/candidaturas/$candidaturaId/buscar-lideres/?busqueda=${Uri.encodeComponent(busqueda)}');
  }

  // Cargar sesión guardada
  Future<bool> loadSavedSession() async {
    if (_storage == null) return false;
    
    final isLoggedIn = await _storage!.isLoggedIn();
    if (!isLoggedIn) return false;
    
    final token = await _storage!.getAuthToken();
    if (token != null) {
      _authToken = token;
      return true;
    }
    return false;
  }

  // Cerrar sesión
  Future<void> logout() async {
    _authToken = null;
    _cookie = null;
    if (_storage != null) {
      await _storage!.clearSession();
    }
  }
}

final apiProvider = Provider<ApiClient>((ref) {
  // API de producción
  const baseUrl = 'https://mivoto.corpofuturo.org';
  final storage = ref.read(storageProvider);
  return ApiClient(baseUrl, storage);
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
  bool _checkingSession = true;

  @override
  void initState() {
    super.initState();
    _checkSavedSession();
  }

  Future<void> _checkSavedSession() async {
    final api = ref.read(apiProvider);
    final hasSession = await api.loadSavedSession();
    
    if (hasSession && mounted) {
      // Si hay sesión guardada, ir directamente al dashboard
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const DashboardScreen()),
      );
    } else {
      setState(() => _checkingSession = false);
    }
  }

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
    if (_checkingSession) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Verificando sesión...'),
            ],
          ),
        ),
      );
    }

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
      appBar: AppBar(
        title: const Text('Candidaturas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              );
            },
            tooltip: 'Mi perfil',
          ),
          IconButton(
            icon: const Icon(Icons.offline_pin),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PendingListScreen()),
              );
            },
            tooltip: 'Ver datos offline',
          ),
        ],
      ),
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

class CandidaturaHome extends ConsumerWidget {
  const CandidaturaHome({super.key, required this.candId});
  final String candId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.watch(apiProvider);
    
    return Scaffold(
      appBar: AppBar(title: const Text('MiVoto - Candidatura')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: api.getJson('/api/me/'),
        builder: (context, meSnap) {
          if (meSnap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          
          Map<String, dynamic>? me = !meSnap.hasError && meSnap.hasData ? meSnap.data : null;
          final vot = (me != null ? me['votante'] as Map<String, dynamic>? : null);
          final role = ((vot?['pertenencia']) ?? '').toString().toLowerCase();
          
          // Control de acceso para el módulo de agendas
          final bool canAccessAgendas = (vot?['es_candidato'] == true) || role == 'agendador';
          
          // Lista de módulos base
          List<Widget> modules = [
            _quickCard(context, Icons.account_tree, 'Mi Jerarquía', () => JerarquiaScreen(candId: candId, candName: '')),
            _quickCard(context, Icons.park, 'Árbol', () => ArbolScreen(candId: candId, candName: '')),
            _quickCard(context, Icons.location_city, 'Jerarquía Localidad', () => JerarquiaLocalidadScreen(candidaturaId: candId, candidaturaName: 'Candidatura')),
            _quickCard(context, Icons.people, 'Votantes', () => VotantesScreen(candId: candId, candName: '')),
          ];
          
          // Solo agregar Agendas si el usuario tiene permisos
          if (canAccessAgendas) {
            modules.add(_quickCard(context, Icons.event, 'Agendas', () => AgendasScreen(candId: candId)));
          }
          
          // Eventos disponible para todos
          modules.add(_quickCard(context, Icons.calendar_today, 'Eventos', () => EventosScreen(candId: candId)));
          
          return GridView.count(
        padding: const EdgeInsets.all(16),
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
            children: modules,
          );
        },
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
        // Solo candidatos o agendadores pueden crear agendas
        final bool canCreate = (vot?['es_candidato'] == true) || role == 'agendador';
        return Scaffold(
          appBar: AppBar(
            title: const Text('Agendas'),
            actions: [
              if (me != null)
                IconButton(
                  icon: const Icon(Icons.info_outline),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Permisos para Agendas'),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Rol: ${role.isEmpty ? 'Sin rol' : role}'),
                            const SizedBox(height: 8),
                            if (canCreate)
                              const Text('✅ Puede crear agendas')
                            else
                              const Text('❌ No puede crear agendas\n(Solo candidatos y agendadores)'),
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
                  tooltip: 'Ver permisos',
                ),
            ],
          ),
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
                        final status = a['status']?.toString() ?? 'not_started';
                        
                        // Colores según estado
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
                          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: ListTile(
                            leading: Icon(statusIcon, color: statusColor, size: 32),
                            title: Text(
                              a['nombre']?.toString() ?? '',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('📅 ${a['fecha'] ?? 'Sin fecha'} ${a['hora_inicio'] ?? ''} - ${a['hora_final'] ?? ''}'),
                                Text('👥 Asistentes: ${a['asistentes_count'] ?? 0}/${a['cantidad_personas'] ?? 0}'),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: statusColor.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: statusColor),
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
                              ],
                            ),
                            trailing: const Icon(Icons.arrow_forward_ios),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => AgendaDetailScreen(agenda: a, candId: candId),
                                ),
                              );
                            },
                          ),
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
  Map<String, dynamic>? _encargadoSeleccionado;
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
  
  // Responsables
  String? _delegadoSeleccionado;
  String? _verificadorSeleccionado;
  String? _logisticaSeleccionado;
  final _requerimientosPublicidad = TextEditingController();
  final _requerimientosLogistica = TextEditingController();
  bool _showResponsables = false;

  @override
  void initState() { super.initState(); _loadLookups(); }

  Future<void> _loadLookups() async {
    try {
      // Intentar cargar desde API
    final api = ref.read(apiProvider);
    final data = await api.lookups();
    setState(() => _lookups = data);
    } catch (e) {
      // Si falla, cargar datos offline
      final storage = ref.read(storageProvider);
      final offlineData = await storage.getLookupsData();
      if (offlineData != null) {
        setState(() => _lookups = offlineData);
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
        'requerimientos_publicidad': _requerimientosPublicidad.text.trim(),
        'requerimientos_logistica': _requerimientosLogistica.text.trim(),
      });
      
      // Asignar responsables si fueron seleccionados
      if (_delegadoSeleccionado != null || _verificadorSeleccionado != null) {
        try {
          // Obtener el ID de la agenda recién creada
          final agendas = await api.getAgendas(widget.candId);
          if (agendas.isNotEmpty) {
            final agendaId = agendas.first['id'] as int;
            
            if (_delegadoSeleccionado != null) {
              await api.asignarDelegado(widget.candId, agendaId, _delegadoSeleccionado!);
            }
            
            if (_verificadorSeleccionado != null) {
              await api.asignarVerificador(widget.candId, agendaId, _verificadorSeleccionado!);
            }
          }
        } catch (e) {
          print('Error asignando responsables: $e');
          // No mostrar error al usuario, la agenda se creó correctamente
        }
      }
      
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
            const SizedBox(height: 12),
            CedulaSelectorWidget(
              controller: _cedulaEncargado,
              candidaturaId: widget.candId,
              labelText: 'Cédula del Encargado',
              hintText: 'Buscar encargado por cédula o nombre...',
              onVotanteSelected: (votante) {
                setState(() {
                  _encargadoSeleccionado = votante;
                });
              },
            ),
            const SizedBox(height: 12),
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
            const SizedBox(height: 16),
            
            // Sección de Responsables (Expandible)
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.people),
                    title: const Text('Responsables (Opcional)'),
                    trailing: Icon(_showResponsables ? Icons.expand_less : Icons.expand_more),
                    onTap: () => setState(() => _showResponsables = !_showResponsables),
                  ),
                  if (_showResponsables) ...[
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          // Delegado
                          RoleSpecificSelectorWidget(
                            candidaturaId: widget.candId,
                            roleFilter: 'delegado',
                            labelText: 'Delegado',
                            hintText: 'Seleccionar delegado...',
                            onVotanteSelected: (votante) {
                              setState(() {
                                _delegadoSeleccionado = votante['id'];
                              });
                            },
                          ),
                          const SizedBox(height: 12),
                          
                          // Verificador
                          RoleSpecificSelectorWidget(
                            candidaturaId: widget.candId,
                            roleFilter: 'verificado',
                            labelText: 'Verificador',
                            hintText: 'Seleccionar verificador...',
                            onVotanteSelected: (votante) {
                              setState(() {
                                _verificadorSeleccionado = votante['id'];
                              });
                            },
                          ),
                          const SizedBox(height: 12),
                          
                          // Logística
                          RoleSpecificSelectorWidget(
                            candidaturaId: widget.candId,
                            roleFilter: 'logistica',
                            labelText: 'Responsable de Logística',
                            hintText: 'Seleccionar responsable de logística...',
                            onVotanteSelected: (votante) {
                              setState(() {
                                _logisticaSeleccionado = votante['id'];
                              });
                            },
                          ),
                          const SizedBox(height: 12),
                          
                          // Requerimientos
                          TextField(
                            controller: _requerimientosPublicidad,
                            decoration: const InputDecoration(
                              labelText: 'Requerimientos de Publicidad',
                              hintText: 'Materiales, equipos, etc.',
                            ),
                            maxLines: 2,
                          ),
                          const SizedBox(height: 12),
                          
                          TextField(
                            controller: _requerimientosLogistica,
                            decoration: const InputDecoration(
                              labelText: 'Requerimientos de Logística',
                              hintText: 'Sillas, sonido, refrigerios, etc.',
                            ),
                            maxLines: 2,
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: _saving ? null : _save, icon: const Icon(Icons.save), label: const Text('Crear')),
          ],
        ),
      ),
    );
  }
}

String _fmtTime(TimeOfDay t) => '${t.hour.toString().padLeft(2,'0')}:${t.minute.toString().padLeft(2,'0')}';

class AgendaDetailScreen extends ConsumerStatefulWidget {
  const AgendaDetailScreen({super.key, required this.agenda, required this.candId});
  final Map<String, dynamic> agenda;
  final String candId;

  @override
  ConsumerState<AgendaDetailScreen> createState() => _AgendaDetailScreenState();
}

class _AgendaDetailScreenState extends ConsumerState<AgendaDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final status = widget.agenda['status']?.toString() ?? 'not_started';
    
    // Colores según estado
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

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.agenda['nombre']?.toString() ?? 'Detalle de Agenda'),
        backgroundColor: statusColor.withOpacity(0.1),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _mostrarInfoAgenda(),
            tooltip: 'Información de la agenda',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Estado de la reunión
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: statusColor),
              ),
              child: Row(
                children: [
                  Icon(statusIcon, color: statusColor, size: 32),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          statusText,
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          widget.agenda['nombre']?.toString() ?? '',
                          style: const TextStyle(fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Información básica
            _buildInfoCard('📅 Fecha y Hora', [
              _buildInfoRow('Fecha', widget.agenda['fecha'] ?? 'No definida'),
              _buildInfoRow('Hora inicio', widget.agenda['hora_inicio'] ?? 'No definida'),
              _buildInfoRow('Hora fin', widget.agenda['hora_final'] ?? 'No definida'),
            ]),
            
            const SizedBox(height: 16),
            
            // Ubicación
            _buildInfoCard('📍 Ubicación', [
              _buildInfoRow('Dirección', widget.agenda['direccion'] ?? 'No definida'),
              _buildInfoRow('Teléfono', widget.agenda['telefono'] ?? 'No definido'),
              if (widget.agenda['ciudad_nombre'] != null) _buildInfoRow('Ciudad', widget.agenda['ciudad_nombre']),
              if (widget.agenda['municipio_nombre'] != null) _buildInfoRow('Municipio', widget.agenda['municipio_nombre']),
              if (widget.agenda['comuna_nombre'] != null) _buildInfoRow('Comuna', widget.agenda['comuna_nombre']),
            ]),
            
            const SizedBox(height: 16),
            
            // Responsables
            // Responsables mejorados
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('👥 Responsables', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue)),
                    const SizedBox(height: 12),
                    
                    // Encargado
                    _buildResponsableRow('🎯 Encargado', widget.agenda['encargado_nombre'] ?? 'No asignado', null),
                    const Divider(height: 20),
                    
                    // Delegado
                    _buildResponsableRow('🤝 Delegado', widget.agenda['delegado_nombre'] ?? 'No asignado', 
                      () => _editarResponsable(context, 'delegado', widget.agenda['id'].toString())),
                    const Divider(height: 20),
                    
                    // Verificador
                    _buildResponsableRow('✅ Verificador', widget.agenda['verificador_nombre'] ?? 'No asignado',
                      () => _editarResponsable(context, 'verificador', widget.agenda['id'].toString())),
                    const Divider(height: 20),
                    
                    // Logística
                    _buildResponsableRow('📦 Logística', widget.agenda['logistica_nombre'] ?? 'No asignado',
                      () => _editarResponsable(context, 'logistica', widget.agenda['id'].toString())),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Capacidad y asistentes
            _buildInfoCard('🎯 Capacidad', [
              _buildInfoRow('Asistentes confirmados', '${widget.agenda['asistentes_count'] ?? 0}'),
              _buildInfoRow('Capacidad total', '${widget.agenda['cantidad_personas'] ?? 0}'),
              _buildInfoRow('Disponibilidad', _getAvailabilityText()),
              _buildInfoRow('Tipo', widget.agenda['privado'] == true ? 'Privada' : 'Pública'),
            ]),
            
            const SizedBox(height: 16),
            
            // Requerimientos
            if ((widget.agenda['requerimientos_publicidad']?.toString() ?? '').isNotEmpty ||
                (widget.agenda['requerimientos_logistica']?.toString() ?? '').isNotEmpty)
              _buildInfoCard('📋 Requerimientos', [
                if ((widget.agenda['requerimientos_publicidad']?.toString() ?? '').isNotEmpty)
                  _buildInfoRow('Publicidad', widget.agenda['requerimientos_publicidad']),
                if ((widget.agenda['requerimientos_logistica']?.toString() ?? '').isNotEmpty)
                  _buildInfoRow('Logística', widget.agenda['requerimientos_logistica']),
              ]),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(String title, List<Widget> children) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value ?? 'No definido',
              style: TextStyle(
                color: (value == null || value.isEmpty) ? Colors.grey : Colors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getAvailabilityText() {
    final asistentes = widget.agenda['asistentes_count'] ?? 0;
    final capacidad = widget.agenda['cantidad_personas'] ?? 0;
    
    if (capacidad == 0) return 'Sin límite definido';
    
    final porcentaje = (asistentes / capacidad * 100).round();
    
    if (porcentaje > 100) {
      return '⚠️ Sobrecupo ($porcentaje%)';
    } else if (porcentaje >= 90) {
      return '🔴 Casi lleno ($porcentaje%)';
    } else if (porcentaje >= 70) {
      return '🟡 Ocupado ($porcentaje%)';
    } else {
      return '🟢 Disponible ($porcentaje%)';
    }
  }

  Widget _buildResponsableRow(String titulo, String nombre, VoidCallback? onEdit) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titulo, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
              const SizedBox(height: 4),
              Text(
                nombre,
                style: TextStyle(
                  color: nombre == 'No asignado' ? Colors.grey : Colors.black87,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
        if (onEdit != null)
          IconButton(
            onPressed: onEdit,
            icon: Icon(
              nombre == 'No asignado' ? Icons.person_add : Icons.edit,
              color: Colors.blue,
            ),
            tooltip: nombre == 'No asignado' ? 'Asignar' : 'Cambiar',
          ),
      ],
    );
  }

  void _editarResponsable(BuildContext context, String tipoResponsable, String agendaId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Asignar ${_getTituloResponsable(tipoResponsable)}'),
        content: SizedBox(
          width: double.maxFinite,
          child: RoleSpecificSelectorWidget(
            candidaturaId: widget.candId,
            roleFilter: _getRoleFilter(tipoResponsable),
            labelText: 'Seleccionar ${_getTituloResponsable(tipoResponsable)}',
            onVotanteSelected: (votante) async {
              Navigator.of(context).pop();
              await _asignarResponsable(tipoResponsable, agendaId, votante['id'].toString());
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }

  String _getTituloResponsable(String tipo) {
    switch (tipo) {
      case 'delegado': return 'Delegado';
      case 'verificador': return 'Verificador';
      case 'logistica': return 'Responsable de Logística';
      default: return tipo;
    }
  }

  String _getRoleFilter(String tipo) {
    switch (tipo) {
      case 'delegado': return 'delegado';
      case 'verificador': return 'verificado';
      case 'logistica': return 'logistica';
      default: return '';
    }
  }

  Future<void> _asignarResponsable(String tipo, String agendaId, String votanteId) async {
    try {
      final api = ref.read(apiProvider);
      
      switch (tipo) {
        case 'delegado':
          await api.asignarDelegado(widget.candId, int.parse(agendaId), votanteId);
          break;
        case 'verificador':
          await api.asignarVerificador(widget.candId, int.parse(agendaId), votanteId);
          break;
        case 'logistica':
          // Por ahora usar el mismo endpoint que delegado hasta que se implemente en el backend
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Funcionalidad de logística en desarrollo')),
          );
          return;
      }
      
      // Recargar datos
      setState(() {});
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_getTituloResponsable(tipo)} asignado correctamente')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al asignar ${_getTituloResponsable(tipo)}: $e')),
      );
    }
  }

  void _mostrarInfoAgenda() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Información de la Agenda'),
        content: const Text('La edición completa de agendas estará disponible en una próxima actualización. Por ahora puedes gestionar los responsables usando los botones correspondientes.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }
}

