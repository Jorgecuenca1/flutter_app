import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'main.dart';
import 'offline_app.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});
  
  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  Map<String, dynamic>? _userData;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final api = ref.read(apiProvider);
      final data = await api.me();
      setState(() {
        _userData = data;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _logout() async {
    final api = ref.read(apiProvider);
    await api.logout();
    
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi Perfil'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadUserData,
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                      const SizedBox(height: 16),
                      Text('Error: $_error', textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadUserData,
                        child: const Text('Reintentar'),
                      ),
                    ],
                  ),
                )
              : _userData == null
                  ? const Center(child: Text('No hay datos de usuario'))
                  : RefreshIndicator(
                      onRefresh: _loadUserData,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Información personal
                            _buildInfoCard(
                              '👤 Información Personal',
                              [
                                _buildInfoRow('Nombre completo', '${_userData!['first_name'] ?? ''} ${_userData!['last_name'] ?? ''}'),
                                _buildInfoRow('Usuario', _userData!['username'] ?? ''),
                                _buildInfoRow('Email', _userData!['email'] ?? ''),
                                _buildInfoRow('Activo', _userData!['is_active'] == true ? 'Sí' : 'No'),
                              ],
                            ),
                            
                            const SizedBox(height: 16),
                            
                            // Información como votante
                            if (_userData!['votante'] != null) ...[
                              _buildVotanteInfo(_userData!['votante'] as Map<String, dynamic>),
                              const SizedBox(height: 16),
                            ],
                            
                            // Acciones
                            _buildActionsCard(),
                            
                            const SizedBox(height: 16),
                            
                            // Información de la app
                            _buildAppInfoCard(),
                          ],
                        ),
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

  Widget _buildVotanteInfo(Map<String, dynamic> votante) {
    return _buildInfoCard(
      '🗳️ Información Electoral',
      [
        _buildInfoRow('Identificación', votante['identificacion'] ?? ''),
        _buildInfoRow('Nombres', votante['nombres'] ?? ''),
        _buildInfoRow('Apellidos', votante['apellidos'] ?? ''),
        _buildInfoRow('Celular', votante['numero_celular'] ?? ''),
        _buildInfoRow('Email', votante['email'] ?? ''),
        _buildInfoRow('Rol/Pertenencia', votante['pertenencia'] ?? 'Sin rol asignado'),
        _buildInfoRow('Es Jefe', votante['es_jefe'] == true ? 'Sí' : 'No'),
        _buildInfoRow('Es Candidato', votante['es_candidato'] == true ? 'Sí' : 'No'),
        if (votante['ciudad_nombre'] != null) 
          _buildInfoRow('Ciudad', votante['ciudad_nombre']),
        if (votante['municipio_nombre'] != null) 
          _buildInfoRow('Municipio', votante['municipio_nombre']),
        if (votante['comuna_nombre'] != null) 
          _buildInfoRow('Comuna', votante['comuna_nombre']),
      ],
    );
  }

  Widget _buildActionsCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '⚙️ Acciones',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.offline_pin, color: Colors.orange),
              title: const Text('Ver datos offline'),
              subtitle: const Text('Revisar votantes y agendas pendientes'),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PendingListScreen()),
                );
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Cerrar sesión'),
              subtitle: const Text('Salir de la aplicación'),
              onTap: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Cerrar sesión'),
                    content: const Text('¿Estás seguro de que quieres cerrar sesión?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancelar'),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          _logout();
                        },
                        child: const Text('Cerrar sesión'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppInfoCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ℹ️ Información de la App',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
            const SizedBox(height: 12),
            _buildInfoRow('Versión', '1.0.0'),
            _buildInfoRow('Servidor', 'mivoto.corpofuturo.org'),
            _buildInfoRow('Modo offline', 'Habilitado'),
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
}



