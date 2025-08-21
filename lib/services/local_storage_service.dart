import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class LocalStorageService {
  static const _kAuthToken = 'auth_token';
  static const _kUserData = 'user_data';
  static const _kPendingVotantes = 'pending_votantes';
  static const _kPendingAgendas = 'pending_agendas';
  static const _kCacheVotantes = 'cache_votantes';
  static const _kCacheAgendas = 'cache_agendas';

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
}


