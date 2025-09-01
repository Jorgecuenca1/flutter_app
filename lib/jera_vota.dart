import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'main.dart';
import 'offline_app.dart';
import 'votante_detail.dart';

class JerarquiaScreen extends ConsumerStatefulWidget {
  const JerarquiaScreen({super.key, required this.candId, required this.candName});
  final String candId;
  final String candName;

  @override
  ConsumerState<JerarquiaScreen> createState() => _JerarquiaScreenState();
}

class _JerarquiaScreenState extends ConsumerState<JerarquiaScreen> {
  List<Map<String, dynamic>> _hierarchyData = [];
  Map<String, dynamic>? _userData;
  bool _isLoading = true;
  String? _error;
  String _selectedFilter = 'todos'; // todos, por_localidad
  Map<String, List<Map<String, dynamic>>> _groupedByLocalidad = {};

  @override
  void initState() {
    super.initState();
    _loadHierarchy();
  }

  Future<void> _loadHierarchy() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final api = ref.read(apiProvider);
      final storage = ref.read(storageProvider);
      
      // Obtener datos del usuario actual
      _userData = await storage.getCachedUserData();
      if (_userData == null) {
        _userData = await api.me();
        await storage.cacheUserData(_userData!);
      }
      
      final currentUserId = _userData?['id']?.toString() ?? 
                           _userData?['votante']?['id']?.toString();
      
      if (currentUserId == null) {
        throw Exception('No se pudo obtener el ID del usuario actual');
      }

      // Intentar cargar desde la API primero
      try {
        final allVotantes = await api.votantesList(widget.candId);
        
        // Guardar en cache y calcular jerarquía
        await storage.cacheVotantesWithHierarchy(widget.candId, allVotantes, currentUserId);
        _hierarchyData = await storage.getVotantesHierarchy(widget.candId, currentUserId);
      } catch (e) {
        // Si falla la API, usar datos locales
        print('⚠️ Error cargando desde API, usando datos locales: $e');
        _hierarchyData = await storage.getVotantesHierarchy(widget.candId, currentUserId);
      }

      // Agrupar por localidad
      _groupByLocalidad();

    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _groupByLocalidad() {
    _groupedByLocalidad.clear();
    
    for (final votante in _hierarchyData) {
      final ciudadNombre = votante['ciudad_nombre']?.toString() ?? 'Sin ciudad';
      final municipioNombre = votante['municipio_nombre']?.toString() ?? 'Sin municipio';
      final comunaNombre = votante['comuna_nombre']?.toString() ?? 'Sin comuna';
      
      final localidadKey = '$ciudadNombre > $municipioNombre > $comunaNombre';
      
      _groupedByLocalidad.putIfAbsent(localidadKey, () => []).add(votante);
    }
    
    // Ordenar cada grupo por nivel jerárquico
    _groupedByLocalidad.forEach((key, value) {
      value.sort((a, b) => (a['hierarchy_level'] ?? 1).compareTo(b['hierarchy_level'] ?? 1));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Jerarquía - ${widget.candName}'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list),
            onSelected: (value) {
              setState(() {
                _selectedFilter = value;
              });
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'todos',
                child: Row(
                  children: [
                    Icon(Icons.account_tree),
                    SizedBox(width: 8),
                    Text('Ver árbol completo'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'por_localidad',
                child: Row(
                  children: [
                    Icon(Icons.location_city),
                    SizedBox(width: 8),
                    Text('Agrupar por localidad'),
                  ],
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadHierarchy,
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Cargando jerarquía...'),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text('Error: $_error'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadHierarchy,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    if (_hierarchyData.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('No tienes votantes en tu jerarquía'),
            SizedBox(height: 8),
            Text(
              'Los votantes que agregues aparecerán aquí',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Header con información
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tu Jerarquía',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${_hierarchyData.length} votantes bajo tu liderazgo',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[600],
                ),
              ),
              if (_selectedFilter == 'por_localidad') ...[
                const SizedBox(height: 4),
                Text(
                  '${_groupedByLocalidad.length} localidades diferentes',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ],
          ),
        ),
        // Contenido principal
        Expanded(
          child: _selectedFilter == 'todos' 
              ? _buildTreeView() 
              : _buildLocalidadView(),
        ),
      ],
    );
  }

  Widget _buildTreeView() {
    // Organizar por niveles jerárquicos
          final byLevel = <int, List<Map<String, dynamic>>>{};
    for (final votante in _hierarchyData) {
      final level = votante['hierarchy_level'] ?? 1;
      byLevel.putIfAbsent(level, () => []).add(votante);
    }

          final levels = byLevel.keys.toList()..sort();

          return ListView.builder(
      padding: const EdgeInsets.all(8),
            itemCount: levels.length,
      itemBuilder: (context, index) {
        final level = levels[index];
        final votantes = byLevel[level]!;
        
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: ExpansionTile(
            leading: CircleAvatar(
              backgroundColor: _getLevelColor(level),
              child: Text(
                '$level',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Text(
              'Nivel $level',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text('${votantes.length} votantes'),
            initiallyExpanded: level <= 2, // Expandir los primeros 2 niveles
            children: votantes.map((votante) => _buildVotanteTile(votante, level)).toList(),
          ),
        );
      },
    );
  }

  Widget _buildLocalidadView() {
    final localidades = _groupedByLocalidad.keys.toList()..sort();

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: localidades.length,
      itemBuilder: (context, index) {
        final localidad = localidades[index];
        final votantes = _groupedByLocalidad[localidad]!;
        
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: ExpansionTile(
            leading: const Icon(Icons.location_on, color: Colors.blue),
            title: Text(
              localidad,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text('${votantes.length} votantes'),
            initiallyExpanded: localidades.length <= 3, // Expandir si hay pocas localidades
            children: votantes.map((votante) => _buildVotanteTile(
              votante, 
              votante['hierarchy_level'] ?? 1,
              showLevel: true,
                )).toList(),
          ),
        );
      },
    );
  }

  Widget _buildVotanteTile(Map<String, dynamic> votante, int level, {bool showLevel = false}) {
    final nombres = votante['nombres']?.toString() ?? 'Sin nombre';
    final apellidos = votante['apellidos']?.toString() ?? 'Sin apellido';
    final identificacion = votante['identificacion']?.toString() ?? 'Sin ID';
    final esJefe = votante['es_jefe'] == true;
    final pertenencia = votante['pertenencia']?.toString() ?? '';
    final nivelJefe = votante['nivel_jefe']?.toString() ?? '';
    
    // Información de localidad
    final ciudadNombre = votante['ciudad_nombre']?.toString() ?? '';
    final municipioNombre = votante['municipio_nombre']?.toString() ?? '';
    final comunaNombre = votante['comuna_nombre']?.toString() ?? '';

    return Container(
      margin: EdgeInsets.only(left: showLevel ? 0 : (level - 1) * 16.0),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: esJefe ? Colors.orange : Colors.blue,
          child: Icon(
            esJefe ? Icons.star : Icons.person,
            color: Colors.white,
            size: 20,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                '$nombres $apellidos',
                style: TextStyle(
                  fontWeight: esJefe ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
            if (showLevel) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _getLevelColor(level),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'N$level',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('📱 $identificacion'),
            if (pertenencia.isNotEmpty) Text('🏷️ $pertenencia'),
            if (esJefe && nivelJefe.isNotEmpty) Text('⭐ Jefe $nivelJefe'),
            if (ciudadNombre.isNotEmpty || municipioNombre.isNotEmpty || comunaNombre.isNotEmpty)
              Text('📍 $ciudadNombre > $municipioNombre > $comunaNombre'),
          ],
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => VotanteDetailScreen(
                candId: widget.candId,
                candName: widget.candName,
                votanteId: votante['id']?.toString() ?? '',
              ),
            ),
          );
        },
      ),
    );
  }

  Color _getLevelColor(int level) {
    final colors = [
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.red,
      Colors.teal,
      Colors.indigo,
      Colors.pink,
    ];
    return colors[(level - 1) % colors.length];
  }
}