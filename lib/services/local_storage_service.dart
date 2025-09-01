import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class LocalStorageService {
  static const _kAuthToken = 'auth_token';
  static const _kUserData = 'user_data';
  static const _kPendingVotantes = 'pending_votantes';
  static const _kPendingAgendas = 'pending_agendas';
  static const _kCacheVotantes = 'cache_votantes';
  static const _kCacheAgendas = 'cache_agendas';
  static const _kLookupsData = 'lookups_data';
  static const _kIsLoggedIn = 'is_logged_in';
  static const _kCacheCandidaturas = 'cache_candidaturas';
  static const _kCacheUserData = 'cache_user_data';

  Future<void> saveAuthToken(String token) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kAuthToken, token);
  }

  Future<String?> getAuthToken() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getString(_kAuthToken);
  }

  Future<void> saveUserData(Map<String, dynamic> user) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kUserData, jsonEncode(user));
  }

  Future<Map<String, dynamic>?> getUserData() async {
    final sp = await SharedPreferences.getInstance();
    final s = sp.getString(_kUserData);
    if (s == null) return null;
    return jsonDecode(s) as Map<String, dynamic>;
  }

  // Pending Votantes
  Future<List<Map<String, dynamic>>> getPendingVotantes() async {
    final sp = await SharedPreferences.getInstance();
    final s = sp.getString(_kPendingVotantes);
    if (s == null) return [];
    final list = (jsonDecode(s) as List).cast<Map<String, dynamic>>();
    return list;
  }

  Future<void> savePendingVotantes(List<Map<String, dynamic>> list) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kPendingVotantes, jsonEncode(list));
  }

  // Método para limpiar votantes pendientes (útil para debugging)
  Future<void> clearPendingVotantes() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_kPendingVotantes);
    print('🧹 Lista de votantes pendientes limpiada');
  }

  Future<void> removePendingVotanteAt(int index) async {
    final list = await getPendingVotantes();
    if (index >= 0 && index < list.length) {
      list.removeAt(index);
      await savePendingVotantes(list);
    }
  }

  // Pending Agendas
  Future<List<Map<String, dynamic>>> getPendingAgendas() async {
    final sp = await SharedPreferences.getInstance();
    final s = sp.getString(_kPendingAgendas);
    if (s == null) return [];
    final list = (jsonDecode(s) as List).cast<Map<String, dynamic>>();
    return list;
  }

  Future<void> savePendingAgendas(List<Map<String, dynamic>> list) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kPendingAgendas, jsonEncode(list));
  }

  Future<void> removePendingAgendaAt(int index) async {
    final list = await getPendingAgendas();
    if (index >= 0 && index < list.length) {
      list.removeAt(index);
      await savePendingAgendas(list);
    }
  }

  // Cache
  Future<void> cacheVotantes(String candId, List<Map<String, dynamic>> list) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('$_kCacheVotantes:$candId', jsonEncode(list));
  }

  Future<List<Map<String, dynamic>>> getCachedVotantes(String candId) async {
    final sp = await SharedPreferences.getInstance();
    final s = sp.getString('$_kCacheVotantes:$candId');
    if (s == null) return [];
    return (jsonDecode(s) as List).cast<Map<String, dynamic>>();
  }

  Future<void> cacheAgendas(String candId, List<Map<String, dynamic>> list) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('$_kCacheAgendas:$candId', jsonEncode(list));
  }

  Future<List<Map<String, dynamic>>> getCachedAgendas(String candId) async {
    final sp = await SharedPreferences.getInstance();
    final s = sp.getString('$_kCacheAgendas:$candId');
    if (s == null) return [];
    return (jsonDecode(s) as List).cast<Map<String, dynamic>>();
  }

  // Lookups (datos de localidad) para uso offline
  Future<void> saveLookupsData(Map<String, dynamic> lookups) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kLookupsData, jsonEncode(lookups));
  }

  Future<Map<String, dynamic>?> getLookupsData() async {
    final sp = await SharedPreferences.getInstance();
    final s = sp.getString(_kLookupsData);
    if (s == null) return null;
    return jsonDecode(s) as Map<String, dynamic>;
  }

  // Persistencia de sesión
  Future<void> setLoggedIn(bool isLoggedIn) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kIsLoggedIn, isLoggedIn);
  }

  Future<bool> isLoggedIn() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getBool(_kIsLoggedIn) ?? false;
  }

  Future<void> clearSession() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_kAuthToken);
    await sp.remove(_kUserData);
    await sp.setBool(_kIsLoggedIn, false);
  }

  // Obtener lista de votantes pendientes con información completa para mostrar
  Future<List<Map<String, dynamic>>> getPendingVotantesWithDetails() async {
    final pending = await getPendingVotantes();
    final lookups = await getLookupsData();
    
    if (lookups == null) return pending;
    
    final ciudades = (lookups['ciudades'] as List?) ?? [];
    final municipios = (lookups['municipios'] as List?) ?? [];
    final comunas = (lookups['comunas'] as List?) ?? [];
    
    return pending.map((votante) {
      final result = Map<String, dynamic>.from(votante);
      
      // Agregar nombres de localidad
      if (votante['ciudad_id'] != null) {
        final ciudad = ciudades.firstWhere(
          (c) => c['id'] == votante['ciudad_id'], 
          orElse: () => null
        );
        if (ciudad != null) result['ciudad_nombre'] = ciudad['nombre'];
      }
      
      if (votante['municipio_id'] != null) {
        final municipio = municipios.firstWhere(
          (m) => m['id'] == votante['municipio_id'], 
          orElse: () => null
        );
        if (municipio != null) result['municipio_nombre'] = municipio['nombre'];
      }
      
      if (votante['comuna_id'] != null) {
        final comuna = comunas.firstWhere(
          (c) => c['id'] == votante['comuna_id'], 
          orElse: () => null
        );
        if (comuna != null) result['comuna_nombre'] = comuna['nombre'];
      }
      
      return result;
    }).toList();
  }

  // Cache de candidaturas
  Future<void> cacheCandidaturas(List<dynamic> candidaturas) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kCacheCandidaturas, jsonEncode(candidaturas));
  }

  Future<List<dynamic>> getCachedCandidaturas() async {
    final sp = await SharedPreferences.getInstance();
    final s = sp.getString(_kCacheCandidaturas);
    if (s == null) return [];
    return jsonDecode(s) as List<dynamic>;
  }

  // Cache de datos de usuario (me)
  Future<void> cacheUserData(Map<String, dynamic> userData) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kCacheUserData, jsonEncode(userData));
  }

  Future<Map<String, dynamic>?> getCachedUserData() async {
    final sp = await SharedPreferences.getInstance();
    final s = sp.getString(_kCacheUserData);
    if (s == null) return null;
    return jsonDecode(s) as Map<String, dynamic>;
  }

  // Métodos para jerarquía de votantes
  Future<void> cacheVotantesWithHierarchy(String candId, List<dynamic> votantes, String currentUserId) async {
    final sp = await SharedPreferences.getInstance();
    
    // Guardar todos los votantes
    await sp.setString('$_kCacheVotantes:$candId', jsonEncode(votantes));
    
    // Calcular y guardar jerarquía del usuario actual
    final hierarchy = _calculateHierarchy(votantes, currentUserId);
    await sp.setString('${_kCacheVotantes}_hierarchy:$candId:$currentUserId', jsonEncode(hierarchy));
  }

  // Agregar un votante a la jerarquía local con candId específico
  Future<void> addVotanteToHierarchyWithCandId(Map<String, dynamic> newVotante, String currentUserId, String candId) async {
    final sp = await SharedPreferences.getInstance();
    
    print('🔍 Agregando votante a jerarquía con candId: $candId');
    
    // Obtener jerarquía actual
    final currentHierarchy = await getVotantesHierarchy(candId, currentUserId);
    
    // Agregar el nuevo votante con nivel 1
    final votanteWithLevel = Map<String, dynamic>.from(newVotante);
    votanteWithLevel['hierarchy_level'] = 1;
    
    currentHierarchy.add(votanteWithLevel);
    print('✅ Agregando votante a jerarquía local: ${newVotante['nombres']?.toString() ?? 'Sin nombre'} ${newVotante['apellidos']?.toString() ?? 'Sin apellido'}');
    
    // Guardar jerarquía actualizada
    await sp.setString('${_kCacheVotantes}_hierarchy:$candId:$currentUserId', jsonEncode(currentHierarchy));
  }

  // Agregar un votante a la jerarquía local (para uso inmediato)
  Future<void> addVotanteToHierarchy(Map<String, dynamic> newVotante, String currentUserId) async {
    final sp = await SharedPreferences.getInstance();
    
    // Obtener el candId del usuario actual
    final userData = await getCachedUserData();
    print('🔍 userData completo: $userData');
    final candId = userData?['votante']?['candidatura_id']?.toString() ?? 
                   userData?['votante']?['candidatura']?.toString();
    
    print('🔍 candId obtenido: $candId');
    if (candId == null) {
      print('❌ No se pudo obtener candId para agregar votante a jerarquía');
      print('❌ Estructura de userData: ${userData?.keys}');
      print('❌ Estructura de votante: ${userData?['votante']?.keys}');
      return;
    }
    
    // Obtener jerarquía actual
    final currentHierarchy = await getVotantesHierarchy(candId, currentUserId);
    
    // Agregar el nuevo votante con nivel 1
    final votanteWithLevel = Map<String, dynamic>.from(newVotante);
    votanteWithLevel['hierarchy_level'] = 1;
    
    currentHierarchy.add(votanteWithLevel);
    
    print('✅ Agregando votante a jerarquía local: ${newVotante['nombres']} ${newVotante['apellidos']}');
    
    // Guardar la jerarquía actualizada
    await sp.setString('${_kCacheVotantes}_hierarchy:$candId:$currentUserId', jsonEncode(currentHierarchy));
  }

  Future<List<Map<String, dynamic>>> getVotantesHierarchy(String candId, String currentUserId) async {
    final sp = await SharedPreferences.getInstance();
    final s = sp.getString('${_kCacheVotantes}_hierarchy:$candId:$currentUserId');
    if (s == null) return [];
    return (jsonDecode(s) as List).cast<Map<String, dynamic>>();
  }

  List<Map<String, dynamic>> _calculateHierarchy(List<dynamic> allVotantes, String currentUserId) {
    final hierarchy = <Map<String, dynamic>>[];
    final visited = <String>{};
    
    print('=== DEBUG JERARQUIA ===');
    print('Current User ID: $currentUserId');
    print('Total votantes: ${allVotantes.length}');
    
    // Función recursiva para encontrar todos los descendientes
    void findDescendants(String userId, int level) {
      if (visited.contains(userId)) return;
      visited.add(userId);
      
      print('Buscando votantes que tienen como líder a: $userId (nivel $level)');
      
      // Buscar todos los votantes que tienen a userId como líder
      final subordinados = <Map<String, dynamic>>[];
      
      for (final votante in allVotantes) {
        final v = votante as Map<String, dynamic>;
        final votanteId = v['id']?.toString();
        final lideres = (v['lideres'] as List?) ?? [];
        
        // Si este votante tiene al usuario actual como líder
        if (votanteId != null && 
            votanteId != userId && 
            !visited.contains(votanteId) &&
            lideres.contains(userId)) {
          subordinados.add(v);
        }
      }
      
      print('  Encontrados ${subordinados.length} votantes con $userId como líder');
      
      for (final subordinado in subordinados) {
        final subId = subordinado['id']?.toString();
        if (subId != null && !visited.contains(subId)) {
          final votanteWithLevel = Map<String, dynamic>.from(subordinado);
          votanteWithLevel['hierarchy_level'] = level;
          hierarchy.add(votanteWithLevel);
          
          print('    ➕ Agregado: ${subordinado['nombres']?.toString() ?? 'Sin nombre'} ${subordinado['apellidos']?.toString() ?? 'Sin apellido'} (Nivel: $level)');
          
          // Buscar descendientes de este subordinado
          findDescendants(subId, level + 1);
        }
      }
    }
    
    // Empezar desde el usuario actual (nivel 1)
    findDescendants(currentUserId, 1);
    
    print('Jerarquía final: ${hierarchy.length} votantes');
    for (final v in hierarchy) {
      print('  - ${v['nombres']?.toString() ?? 'Sin nombre'} ${v['apellidos']?.toString() ?? 'Sin apellido'} (Nivel: ${v['hierarchy_level']})');
    }
    print('========================');
    
    return hierarchy;
  }

  Future<void> saveCurrentUserId(String userId) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('current_user_id', userId);
  }

  Future<String?> getCurrentUserId() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getString('current_user_id');
  }
}


