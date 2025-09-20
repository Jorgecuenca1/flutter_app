import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'jera_vota.dart';
import 'votantes.dart';
import 'jerarquia_localidad.dart';
import 'arbol_screen.dart';
import 'offline_app.dart';
import 'profile_screen.dart';
import 'services/local_storage_service.dart';
import 'screens/map_votantes_screen.dart';
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
  
  Future<Map<String, dynamic>> agendaGet(String candId, int agendaId) async {
    final response = await getJson('/api/candidaturas/$candId/agendas/$agendaId/');
    return response['agenda'] ?? {};
  }
  
  Future<void> agendaUpdate(String candId, int agendaId, Map<String, dynamic> payload) async {
    await putJson('/api/candidaturas/$candId/agendas/$agendaId/', payload);
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

  Future<List<Map<String, dynamic>>> buscarVotantes(String candId, String query) async {
    final response = await getJson('/api/candidaturas/$candId/buscar-votantes/?q=${Uri.encodeComponent(query)}');
    return List<Map<String, dynamic>>.from(response['votantes'] ?? []);
  }
  
  Future<List<Map<String, dynamic>>> getVotantesPorRol(String candId, String rol) async {
    final response = await getJson('/api/candidaturas/$candId/buscar-votantes-por-rol/?rol=${Uri.encodeComponent(rol)}');
    return List<Map<String, dynamic>>.from(response['votantes'] ?? []);
  }
  
  Future<List<Map<String, dynamic>>> buscarVotantesPorRol(String candId, String rol, String query) async {
    final response = await getJson('/api/candidaturas/$candId/buscar-votantes-por-rol/?rol=${Uri.encodeComponent(rol)}&q=${Uri.encodeComponent(query)}');
    return List<Map<String, dynamic>>.from(response['votantes'] ?? []);
  }
  
  Future<void> asignarDelegado(String candId, int agendaId, String votanteId) async {
    await putJson('/api/candidaturas/$candId/agendas/$agendaId/', {
      'delegado_id': votanteId,
    });
  }
  
  Future<void> asignarVerificador(String candId, int agendaId, String votanteId) async {
    await putJson('/api/candidaturas/$candId/agendas/$agendaId/', {
      'verificador_id': votanteId,
    });
  }
  
  Future<List<Map<String, dynamic>>> getAsistentesAgenda(String candId, int agendaId) async {
    final response = await getJson('/api/candidaturas/$candId/agendas/$agendaId/asistentes/');
    return List<Map<String, dynamic>>.from(response['asistentes'] ?? []);
  }
  
  Future<void> agregarAsistente(String candId, int agendaId, String identificacion) async {
    await postJson('/api/candidaturas/$candId/agendas/$agendaId/asistentes/', {
      'identificacion': identificacion,
    });
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
  // API local para desarrollo
  const baseUrl = 'http://localhost:8003';
  // API de producción
  // const baseUrl = 'https://mivoto.corpofuturo.org';
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
          
          // Mapa de votantes con ubicación
          modules.add(_quickCard(context, Icons.map, 'Mapa Votantes', () => MapVotantesScreen(candId: candId, candName: '')));
          
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
  const AgendaForm({super.key, required this.candId, this.agenda});
  final String candId;
  final Map<String, dynamic>? agenda; // Para edición
  @override
  ConsumerState<AgendaForm> createState() => _AgendaFormState();
}

class _AgendaFormState extends ConsumerState<AgendaForm> {
  final _nombre = TextEditingController();
  final _cedulaEncargado = TextEditingController();
  final _direccion = TextEditingController();
  final _telefono = TextEditingController();
  final _requerimientosPublicidad = TextEditingController();
  final _requerimientosLogistica = TextEditingController();
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
  bool get isEditing => widget.agenda != null;
  
  // Para el buscador de encargados
  List<Map<String, dynamic>> _votantesSugeridos = [];
  Map<String, dynamic>? _encargadoSeleccionado;
  bool _buscandoVotantes = false;
  Timer? _debounceTimer;
  
  // Nuevos campos para delegado, verificador y logística
  Map<String, dynamic>? _delegadoSeleccionado;
  Map<String, dynamic>? _verificadorSeleccionado;
  Map<String, dynamic>? _logisticaSeleccionado;
  List<Map<String, dynamic>> _delegadosSugeridos = [];
  List<Map<String, dynamic>> _verificadoresSugeridos = [];
  List<Map<String, dynamic>> _logisticaSugeridos = [];
  bool _buscandoDelegados = false;
  bool _buscandoVerificadores = false;
  bool _buscandoLogistica = false;

  @override
  void initState() { 
    super.initState(); 
    _loadLookups();
    if (isEditing && widget.agenda != null) {
      _loadAgendaData();
    }
  }
  
  void _loadAgendaData() {
    final agenda = widget.agenda!;
    _nombre.text = agenda['nombre'] ?? '';
    _cedulaEncargado.text = agenda['encargado_cedula'] ?? '';
    // Si hay encargado, guardar su información
    if (agenda['encargado'] != null) {
      _encargadoSeleccionado = {
        'id': agenda['encargado'],
        'identificacion': agenda['encargado_cedula'],
        'nombres': agenda['encargado_nombre']?.split(' ').first ?? '',
        'apellidos': agenda['encargado_nombre']?.split(' ').skip(1).join(' ') ?? '',
      };
    }
    _direccion.text = agenda['direccion'] ?? '';
    _telefono.text = agenda['telefono'] ?? '';
    _requerimientosPublicidad.text = agenda['requerimientos_publicidad'] ?? '';
    _requerimientosLogistica.text = agenda['requerimientos_logistica'] ?? '';
    _ciudadId = agenda['ciudad'];
    _municipioId = agenda['municipio'];
    _comunaId = agenda['comuna'];
    _capacidad = agenda['cantidad_personas'] ?? 0;
    _privado = agenda['privado'] ?? false;
    
    if (agenda['fecha'] != null) {
      _fecha = DateTime.tryParse(agenda['fecha']);
    }
    if (agenda['hora_inicio'] != null) {
      final parts = agenda['hora_inicio'].toString().split(':');
      if (parts.length >= 2) {
        _inicio = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
      }
    }
    if (agenda['hora_final'] != null) {
      final parts = agenda['hora_final'].toString().split(':');
      if (parts.length >= 2) {
        _fin = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
      }
    }
    
    // Cargar roles asignados
    if (agenda['delegado_id'] != null) {
      _delegadoSeleccionado = {
        'id': agenda['delegado_id'],
        'nombres': agenda['delegado_nombre']?.split(' ').first ?? '',
        'apellidos': agenda['delegado_nombre']?.split(' ').skip(1).join(' ') ?? '',
      };
    }
    if (agenda['verificador_id'] != null) {
      _verificadorSeleccionado = {
        'id': agenda['verificador_id'],
        'nombres': agenda['verificador_nombre']?.split(' ').first ?? '',
        'apellidos': agenda['verificador_nombre']?.split(' ').skip(1).join(' ') ?? '',
      };
    }
    if (agenda['logistica_id'] != null) {
      _logisticaSeleccionado = {
        'id': agenda['logistica_id'],
        'nombres': agenda['logistica_nombre']?.split(' ').first ?? '',
        'apellidos': agenda['logistica_nombre']?.split(' ').skip(1).join(' ') ?? '',
      };
    }
  }

  Future<void> _buscarVotantes(String query) async {
    if (query.isEmpty) {
      setState(() {
        _votantesSugeridos = [];
        _buscandoVotantes = false;
      });
      return;
    }
    
    setState(() => _buscandoVotantes = true);
    
    try {
      final api = ref.read(apiProvider);
      final votantes = await api.buscarVotantes(widget.candId, query);
      setState(() {
        _votantesSugeridos = votantes;
        _buscandoVotantes = false;
      });
    } catch (e) {
      setState(() {
        _votantesSugeridos = [];
        _buscandoVotantes = false;
      });
    }
  }
  
  void _onCedulaChanged(String value) {
    // Cancelar el timer anterior si existe
    _debounceTimer?.cancel();
    
    // Reiniciar el encargado seleccionado si el texto cambia
    if (_encargadoSeleccionado != null && 
        _encargadoSeleccionado!['identificacion'] != value) {
      _encargadoSeleccionado = null;
    }
    
    // Crear un nuevo timer para buscar después de 500ms
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _buscarVotantes(value);
    });
  }
  
  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

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
      // Validar que se haya seleccionado un encargado
      if (_encargadoSeleccionado == null) {
        throw Exception('Debe seleccionar un encargado para la reunión');
      }
      
      final data = {
        'nombre': _nombre.text.trim().isEmpty ? null : _nombre.text.trim(),
        'cedula_encargado': _encargadoSeleccionado!['identificacion'],
        'direccion': _direccion.text.trim().isEmpty ? null : _direccion.text.trim(),
        'telefono': _telefono.text.trim().isEmpty ? null : _telefono.text.trim(),
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
        'delegado_id': _delegadoSeleccionado?['id'],
        'verificador_id': _verificadorSeleccionado?['id'],
        'logistica_id': _logisticaSeleccionado?['id'],
      };
      
      if (isEditing) {
        // Actualizar agenda existente
        await api.agendaUpdate(widget.candId, widget.agenda!['id'], data);
      } else {
        // Crear nueva agenda
        await api.agendaCreate(widget.candId, data);
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
            TextField(
              controller: _nombre, 
              decoration: InputDecoration(
                labelText: 'Nombre de la reunión (Opcional)',
                helperText: 'Opcional - Ingrese el nombre de la reunión',
                border: OutlineInputBorder(),
              )
            ),
            const SizedBox(height: 12),
            // Campo de búsqueda de encargado con autocompletado
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _cedulaEncargado,
                  onChanged: _onCedulaChanged,
                  decoration: InputDecoration(
                    labelText: 'Buscar Encargado (Obligatorio)',
                    helperText: _encargadoSeleccionado != null
                        ? 'Seleccionado: ${_encargadoSeleccionado!['nombres']} ${_encargadoSeleccionado!['apellidos']}'
                        : 'Busque por cédula o nombre del encargado',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.search),
                    suffixIcon: _buscandoVotantes
                        ? Container(
                            width: 20,
                            height: 20,
                            padding: EdgeInsets.all(12),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : _encargadoSeleccionado != null
                            ? Icon(Icons.check_circle, color: Colors.green)
                            : null,
                  ),
                ),
                if (_votantesSugeridos.isNotEmpty)
                  Container(
                    constraints: BoxConstraints(maxHeight: 200),
                    margin: EdgeInsets.only(top: 4),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _votantesSugeridos.length,
                      itemBuilder: (context, index) {
                        final votante = _votantesSugeridos[index];
                        return ListTile(
                          dense: true,
                          title: Text(
                            '${votante['nombres']} ${votante['apellidos']}',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            'CC: ${votante['identificacion']} - ${votante['ciudad']}',
                          ),
                          trailing: votante['pertenencia'] != null
                              ? Chip(
                                  label: Text(
                                    votante['pertenencia'],
                                    style: TextStyle(fontSize: 11),
                                  ),
                                  padding: EdgeInsets.zero,
                                )
                              : null,
                          onTap: () {
                            setState(() {
                              _encargadoSeleccionado = votante;
                              _cedulaEncargado.text = votante['identificacion'];
                              _votantesSugeridos = [];
                              
                              // Auto-rellenar dirección y teléfono si están disponibles
                              if (votante['direccion'] != null && _direccion.text.isEmpty) {
                                _direccion.text = votante['direccion'];
                              }
                              if (votante['numero_celular'] != null && _telefono.text.isEmpty) {
                                _telefono.text = votante['numero_celular'];
                              }
                            });
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextField(
                controller: _direccion, 
                decoration: InputDecoration(
                  labelText: 'Dirección (Opcional)',
                  border: OutlineInputBorder(),
                )
              )),
              const SizedBox(width: 8),
              Expanded(child: TextField(
                controller: _telefono, 
                decoration: InputDecoration(
                  labelText: 'Teléfono (Opcional)',
                  border: OutlineInputBorder(),
                )
              )),
            ]),
            const SizedBox(height: 12),
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
            const SizedBox(height: 12),
            TextField(
              controller: _requerimientosPublicidad,
              decoration: InputDecoration(
                labelText: 'Requerimientos de Publicidad (Opcional)',
                helperText: 'Opcional - Ingrese los requerimientos de publicidad',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _requerimientosLogistica,
              decoration: InputDecoration(
                labelText: 'Requerimientos de Logística (Opcional)', 
                helperText: 'Opcional - Ingrese los requerimientos de logística',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            
            // Sección de Roles Opcionales
            const Divider(),
            const Text(
              'Roles Opcionales',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            
            // Campo para seleccionar Delegado
            _buildRoleSelector(
              'Delegado (Opcional)',
              _delegadoSeleccionado,
              _delegadosSugeridos,
              _buscandoDelegados,
              'Delegado',
              (selected) => setState(() => _delegadoSeleccionado = selected),
              (sugeridos) => setState(() => _delegadosSugeridos = sugeridos),
              (buscando) => setState(() => _buscandoDelegados = buscando),
            ),
            const SizedBox(height: 12),
            
            // Campo para seleccionar Verificador
            _buildRoleSelector(
              'Verificador (Opcional)',
              _verificadorSeleccionado,
              _verificadoresSugeridos,
              _buscandoVerificadores,
              'Verificado',
              (selected) => setState(() => _verificadorSeleccionado = selected),
              (sugeridos) => setState(() => _verificadoresSugeridos = sugeridos),
              (buscando) => setState(() => _buscandoVerificadores = buscando),
            ),
            const SizedBox(height: 12),
            
            // Campo para seleccionar Logística
            _buildRoleSelector(
              'Logística (Opcional)',
              _logisticaSeleccionado,
              _logisticaSugeridos,
              _buscandoLogistica,
              'Logística',
              (selected) => setState(() => _logisticaSeleccionado = selected),
              (sugeridos) => setState(() => _logisticaSugeridos = sugeridos),
              (buscando) => setState(() => _buscandoLogistica = buscando),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _saving ? null : _save, 
              icon: Icon(isEditing ? Icons.update : Icons.save), 
              label: Text(isEditing ? 'Actualizar' : 'Crear')
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildRoleSelector(
    String label,
    Map<String, dynamic>? selected,
    List<Map<String, dynamic>> sugeridos,
    bool buscando,
    String rol,
    Function(Map<String, dynamic>?) onSelect,
    Function(List<Map<String, dynamic>>) onSugeridosChange,
    Function(bool) onBuscandoChange,
  ) {
    final controller = TextEditingController(
      text: selected != null ? '${selected['nombres']} ${selected['apellidos']}' : '',
    );
    
    Timer? searchTimer;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          onChanged: (value) {
            if (value.isEmpty) {
              onSelect(null);
              onSugeridosChange([]);
              return;
            }
            
            // Cancelar búsqueda anterior
            searchTimer?.cancel();
            
            // Buscar después de 500ms
            searchTimer = Timer(const Duration(milliseconds: 500), () async {
              onBuscandoChange(true);
              try {
                final api = ref.read(apiProvider);
                final votantes = await api.buscarVotantesPorRol(widget.candId, rol, value);
                onSugeridosChange(votantes);
              } catch (e) {
                onSugeridosChange([]);
              } finally {
                onBuscandoChange(false);
              }
            });
          },
          decoration: InputDecoration(
            labelText: label,
            helperText: selected != null
                ? 'Seleccionado: ${selected['nombres']} ${selected['apellidos']}'
                : 'Busque por nombre o cédula',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.search),
            suffixIcon: buscando
                ? Container(
                    width: 20,
                    height: 20,
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : selected != null
                    ? IconButton(
                        icon: Icon(Icons.clear),
                        onPressed: () {
                          controller.clear();
                          onSelect(null);
                          onSugeridosChange([]);
                        },
                      )
                    : null,
          ),
        ),
        if (sugeridos.isNotEmpty)
          Container(
            constraints: BoxConstraints(maxHeight: 150),
            margin: EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(4),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: sugeridos.length,
              itemBuilder: (context, index) {
                final votante = sugeridos[index];
                return ListTile(
                  dense: true,
                  title: Text(
                    '${votante['nombres']} ${votante['apellidos']}',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text('CC: ${votante['identificacion']}'),
                  onTap: () {
                    onSelect(votante);
                    controller.text = '${votante['nombres']} ${votante['apellidos']}';
                    onSugeridosChange([]);
                  },
                );
              },
            ),
          ),
      ],
    );
  }
}

String _fmtTime(TimeOfDay t) => '${t.hour.toString().padLeft(2,'0')}:${t.minute.toString().padLeft(2,'0')}';

class AgendaDetailScreen extends ConsumerWidget {
  const AgendaDetailScreen({super.key, required this.agenda, required this.candId});
  final Map<String, dynamic> agenda;
  final String candId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = agenda['status']?.toString() ?? 'not_started';
    
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
        title: Text(agenda['nombre']?.toString() ?? 'Detalle de Agenda'),
        backgroundColor: statusColor.withOpacity(0.1),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () async {
              final api = ref.read(apiProvider);
              try {
                // Cargar los datos completos de la agenda
                final agendaData = await api.agendaGet(candId, agenda['id']);
                
                if (context.mounted) {
                  final result = await showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    builder: (context) => Padding(
                      padding: EdgeInsets.only(
                        bottom: MediaQuery.of(context).viewInsets.bottom
                      ),
                      child: AgendaForm(candId: candId, agenda: agendaData),
                    ),
                  );
                  
                  // Si se actualizó, volver a la pantalla anterior para recargar
                  if (result != null && context.mounted) {
                    Navigator.of(context).pop(true);
                  }
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error cargando agenda: $e')),
                  );
                }
              }
            },
            tooltip: 'Editar agenda',
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
                          agenda['nombre']?.toString() ?? '',
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
              _buildInfoRow('Fecha', agenda['fecha'] ?? 'No definida'),
              _buildInfoRow('Hora inicio', agenda['hora_inicio'] ?? 'No definida'),
              _buildInfoRow('Hora fin', agenda['hora_final'] ?? 'No definida'),
            ]),
            
            const SizedBox(height: 16),
            
            // Ubicación
            _buildInfoCard('📍 Ubicación', [
              _buildInfoRow('Dirección', agenda['direccion'] ?? 'No definida'),
              _buildInfoRow('Teléfono', agenda['telefono'] ?? 'No definido'),
              if (agenda['ciudad_nombre'] != null) _buildInfoRow('Ciudad', agenda['ciudad_nombre']),
              if (agenda['municipio_nombre'] != null) _buildInfoRow('Municipio', agenda['municipio_nombre']),
              if (agenda['comuna_nombre'] != null) _buildInfoRow('Comuna', agenda['comuna_nombre']),
            ]),
            
            const SizedBox(height: 16),
            
            // Responsables
            _buildInfoCard('👥 Responsables', [
              _buildInfoRow('Encargado', agenda['encargado_nombre'] ?? 'No asignado'),
              _buildInfoRow('Delegado', agenda['delegado_nombre'] ?? 'No asignado'),
              _buildInfoRow('Verificador', agenda['verificador_nombre'] ?? 'No asignado'),
              _buildInfoRow('Logística', agenda['logistica_nombre'] ?? 'No asignado'),
            ]),
            
            const SizedBox(height: 16),
            
            // Capacidad y asistentes
            _buildInfoCard('🎯 Capacidad', [
              _buildInfoRow('Asistentes confirmados', '${agenda['asistentes_count'] ?? 0}'),
              _buildInfoRow('Capacidad total', '${agenda['cantidad_personas'] ?? 0}'),
              _buildInfoRow('Disponibilidad', _getAvailabilityText()),
              _buildInfoRow('Tipo', agenda['privado'] == true ? 'Privada' : 'Pública'),
            ]),
            
            const SizedBox(height: 16),
            
            // Requerimientos
            if ((agenda['requerimientos_publicidad']?.toString() ?? '').isNotEmpty ||
                (agenda['requerimientos_logistica']?.toString() ?? '').isNotEmpty)
              _buildInfoCard('📋 Requerimientos', [
                if ((agenda['requerimientos_publicidad']?.toString() ?? '').isNotEmpty)
                  _buildInfoRow('Publicidad', agenda['requerimientos_publicidad']),
                if ((agenda['requerimientos_logistica']?.toString() ?? '').isNotEmpty)
                  _buildInfoRow('Logística', agenda['requerimientos_logistica']),
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
    final asistentes = agenda['asistentes_count'] ?? 0;
    final capacidad = agenda['cantidad_personas'] ?? 0;
    
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
}

