import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'main.dart';
import 'offline_app.dart';
import 'widgets/export_filter_widget.dart';

class JerarquiaLocalidadScreen extends HookConsumerWidget {
  final String candidaturaId;
  final String candidaturaName;

  const JerarquiaLocalidadScreen({
    Key? key,
    required this.candidaturaId,
    required this.candidaturaName,
  }) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.read(apiProvider);
    final searchController = useTextEditingController();
    final jerarquiaData = useState<Map<String, dynamic>?>(null);
    final resultadosBusqueda = useState<List<dynamic>>([]);
    final isLoading = useState(true);
    final isSearching = useState(false);
    final busquedaActual = useState('');
    final userData = useState<Map<String, dynamic>?>(null);
    final filtroLocalidad = useState<String>('todos'); // todos, ciudad, municipio, comuna, puesto
    
    // Filtros jerárquicos para localidades
    final filtroJerarquicoCiudad = useState<int?>(null);
    final filtroJerarquicoMunicipio = useState<int?>(null);
    final filtroJerarquicoComuna = useState<int?>(null);
    final lookupData = useState<Map<String, dynamic>?>(null);

    // Cargar datos iniciales
    useEffect(() {
      _loadJerarquia() async {
        try {
          final storage = ref.read(storageProvider);
          
          // Obtener datos del usuario actual
          Map<String, dynamic>? userDataLocal = await storage.getCachedUserData();
          if (userDataLocal == null) {
            userDataLocal = await api.me();
            await storage.cacheUserData(userDataLocal);
          }
          userData.value = userDataLocal;
          
          final currentUserId = userDataLocal['id']?.toString() ?? 
                               userDataLocal['votante']?['id']?.toString();
          
          if (currentUserId == null) {
            throw Exception('No se pudo obtener el ID del usuario actual');
          }

          // Intentar cargar desde la API primero
          List<Map<String, dynamic>> hierarchyData = [];
          try {
            final allVotantes = await api.votantesList(candidaturaId);
            
            // Guardar en cache y calcular jerarquía
            await storage.cacheVotantesWithHierarchy(candidaturaId, allVotantes, currentUserId);
            hierarchyData = await storage.getVotantesHierarchy(candidaturaId, currentUserId);
          } catch (e) {
            // Si falla la API, usar datos locales
            print('⚠️ Error cargando desde API, usando datos locales: $e');
            hierarchyData = await storage.getVotantesHierarchy(candidaturaId, currentUserId);
          }

          // Cargar datos de lookup para filtros jerárquicos
          try {
            final lookupsData = await api.lookups();
            lookupData.value = lookupsData;
          } catch (e) {
            // Si falla, intentar cargar desde cache
            final storage = ref.read(storageProvider);
            final cachedLookups = await storage.getLookupsData();
            if (cachedLookups != null) {
              lookupData.value = cachedLookups;
            }
          }

          // Convertir jerarquía a formato de localidad
          print('🔍 JERARQUIA LOCALIDAD - Datos de jerarquía recibidos: ${hierarchyData.length} votantes');
          for (final votante in hierarchyData) {
            print('  - ${votante['nombres']} ${votante['apellidos']} (Nivel: ${votante['hierarchy_level']})');
            print('    🏙️ Ciudad: ${votante['ciudad_nombre']} | Municipio: ${votante['municipio_nombre']} | Comuna: ${votante['comuna_nombre']}');
            print('    🔑 Campos disponibles: ${votante.keys.toList()}');
          }
          
          final localidadData = _convertToLocalidadFormat(
            hierarchyData, 
            filtroLocalidad.value,
            filtroJerarquicoCiudad.value,
            filtroJerarquicoMunicipio.value,
            filtroJerarquicoComuna.value,
          );
          print('🔍 JERARQUIA LOCALIDAD - Datos convertidos: ${localidadData['total_votantes_jerarquia']} votantes');
          jerarquiaData.value = localidadData;
          
        } catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al cargar jerarquía: $e')),
          );
        } finally {
          isLoading.value = false;
        }
      }
      _loadJerarquia();
      return null;
    }, []);

    // Escuchar cambios en los filtros de localidad
    useEffect(() {
      if (jerarquiaData.value != null) {
        // Recalcular datos cuando cambien los filtros
        final storage = ref.read(storageProvider);
        storage.getVotantesHierarchy(candidaturaId, userData.value?['id']?.toString() ?? userData.value?['votante']?['id']?.toString() ?? '').then((hierarchyData) {
          final localidadData = _convertToLocalidadFormat(
            hierarchyData, 
            filtroLocalidad.value,
            filtroJerarquicoCiudad.value,
            filtroJerarquicoMunicipio.value,
            filtroJerarquicoComuna.value,
          );
          jerarquiaData.value = localidadData;
        });
      }
      return null;
    }, [filtroLocalidad.value, filtroJerarquicoCiudad.value, filtroJerarquicoMunicipio.value, filtroJerarquicoComuna.value]);

    // Función de búsqueda
    Future<void> _buscarLideres(String busqueda) async {
      if (busqueda.trim().isEmpty) {
        resultadosBusqueda.value = [];
        busquedaActual.value = '';
        return;
      }

      isSearching.value = true;
      try {
        final data = await api.buscarLideresLocalidad(candidaturaId, busqueda);
        resultadosBusqueda.value = data['resultados'] ?? [];
        busquedaActual.value = busqueda;
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error en búsqueda: $e')),
        );
      } finally {
        isSearching.value = false;
      }
    }

    if (isLoading.value) {
      return Scaffold(
        appBar: AppBar(title: Text('Jerarquía por Localidad')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final usuarioActual = jerarquiaData.value?['usuario_actual'] ?? {};
    final localidades = jerarquiaData.value?['localidades'] as Map<String, dynamic>? ?? {};
    final totalVotantes = jerarquiaData.value?['total_votantes'] ?? 0;
    final totalLideres = jerarquiaData.value?['total_lideres'] ?? 0;
    
    // Debug: imprimir datos para verificar
    print('=== DEBUG JERARQUIA ===');
    print('Total líderes: $totalLideres');
    print('Total votantes: $totalVotantes');
    print('Localidades keys: ${localidades.keys.toList()}');
    print('Localidades count: ${localidades.length}');
    if (localidades.isNotEmpty) {
      final firstKey = localidades.keys.first;
      print('Primera localidad ($firstKey): ${localidades[firstKey]}');
    }
    print('========================');

    // Ordenar localidades por tipo y nombre (el filtro ya se aplicó en _convertToLocalidadFormat)
    final localidadesOrdenadas = localidades.entries.toList()
      ..sort((a, b) {
        final tipoA = a.value['tipo'] ?? '';
        final tipoB = b.value['tipo'] ?? '';
        final nombreA = a.value['nombre'] ?? '';
        final nombreB = b.value['nombre'] ?? '';
        
        // Primero por tipo (ciudad, municipio, comuna, puesto)
        final tipoOrder = ['ciudad', 'municipio', 'comuna', 'puesto_votacion'];
        final orderA = tipoOrder.indexOf(tipoA);
        final orderB = tipoOrder.indexOf(tipoB);
        
        if (orderA != orderB) {
          return orderA.compareTo(orderB);
        }
        
        // Luego por nombre
        return nombreA.compareTo(nombreB);
      });

    return Scaffold(
      appBar: AppBar(
        title: Text('Jerarquía - $candidaturaName'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          isLoading.value = true;
          try {
            final storage = ref.read(storageProvider);
            
            // Obtener datos del usuario actual
            Map<String, dynamic>? userData = await storage.getCachedUserData();
            if (userData == null) {
              userData = await api.me();
              await storage.cacheUserData(userData);
            }
            
            final currentUserId = userData['id']?.toString() ?? 
                                 userData['votante']?['id']?.toString();
            
            if (currentUserId == null) {
              throw Exception('No se pudo obtener el ID del usuario actual');
            }

            // Recargar desde la API
            final allVotantes = await api.votantesList(candidaturaId);
            
            // Guardar en cache y calcular jerarquía
            await storage.cacheVotantesWithHierarchy(candidaturaId, allVotantes, currentUserId);
            final hierarchyData = await storage.getVotantesHierarchy(candidaturaId, currentUserId);

            // Convertir jerarquía a formato de localidad
            print('🔄 REFRESH JERARQUIA LOCALIDAD - Datos de jerarquía: ${hierarchyData.length} votantes');
            final localidadData = _convertToLocalidadFormat(hierarchyData, filtroLocalidad.value);
            jerarquiaData.value = localidadData;
          } finally {
            isLoading.value = false;
          }
        },
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Información del usuario actual
              Card(
                color: Colors.blue.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.person, color: Colors.blue.shade700),
                          const SizedBox(width: 8),
                      Text(
                        'Usuario Actual',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                                  color: Colors.blue.shade700,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (userData.value != null) ...[
                        Text('👤 ${userData.value!['votante']?['nombres'] ?? ''} ${userData.value!['votante']?['apellidos'] ?? ''} (${userData.value!['votante']?['identificacion'] ?? ''})'),
                        Text('📧 ${userData.value!['user'] ?? ''}'),
                        Text('🏷️ Rol: ${userData.value!['votante']?['pertenencia'] ?? 'Sin rol'}'),
                        if (userData.value!['votante']?['es_jefe'] == true)
                          Text('👑 Es Jefe', style: TextStyle(color: Colors.orange.shade700, fontWeight: FontWeight.bold)),
                        if (userData.value!['votante']?['es_candidato'] == true)
                          Text('🎯 Es Candidato', style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.bold)),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '👑 Líderes: $totalLideres',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              '👥 Votantes: $totalVotantes',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Filtros de localidad
              Card(
                color: Colors.green.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.filter_list, color: Colors.green.shade700),
                          const SizedBox(width: 8),
                          Text(
                            'Filtrar por Tipo de Localidad',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green.shade700,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildFiltroChip('todos', '🌍 Todos', filtroLocalidad),
                          _buildFiltroChip('ciudad', '🏙️ Ciudades', filtroLocalidad),
                          _buildFiltroChip('municipio', '🏘️ Municipios', filtroLocalidad),
                          _buildFiltroChip('comuna', '🏠 Comunas', filtroLocalidad),
                          _buildFiltroChip('puesto', '🗳️ Puestos', filtroLocalidad),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Filtros jerárquicos de localidad
              if (lookupData.value != null) ...[
                _buildHierarchicalFilters(
                  lookupData.value!,
                  filtroJerarquicoCiudad,
                  filtroJerarquicoMunicipio,
                  filtroJerarquicoComuna,
                ),
                const SizedBox(height: 16),
              ],

              // Widget de exportación y filtrado
              if (userData.value != null && jerarquiaData.value != null) ...[
                ExportFilterWidget(
                  candidaturaId: candidaturaId,
                  candidaturaName: candidaturaName,
                  hierarchyData: jerarquiaData.value?['jerarquia_completa'] ?? [],
                  userData: userData.value!,
                ),
                const SizedBox(height: 16),
              ],

              // Búsqueda por localidad
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.search, color: Colors.grey.shade600),
                          const SizedBox(width: 8),
                          Text(
                            'Buscar por Localidad',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: searchController,
                              decoration: InputDecoration(
                                hintText: 'Buscar ciudad, municipio o comuna...',
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              onSubmitted: _buscarLideres,
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: isSearching.value 
                              ? null 
                              : () => _buscarLideres(searchController.text),
                            icon: isSearching.value 
                              ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : Icon(Icons.search),
                            label: Text('Buscar'),
                          ),
                          if (busquedaActual.value.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              onPressed: () {
                                searchController.clear();
                                resultadosBusqueda.value = [];
                                busquedaActual.value = '';
                              },
                              icon: Icon(Icons.clear),
                              label: Text('Limpiar'),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.grey),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Resultados de búsqueda
              if (busquedaActual.value.isNotEmpty) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.location_on, color: Colors.red),
                            const SizedBox(width: 8),
                            Text(
                              'Resultados para "${busquedaActual.value}"',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (resultadosBusqueda.value.isEmpty)
                          Container(
                            padding: EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.orange.shade200),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.warning, color: Colors.orange),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'No se encontraron líderes para "${busquedaActual.value}" en tu jurisdicción.',
                                    style: TextStyle(color: Colors.orange.shade800),
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          ...resultadosBusqueda.value.map((resultado) => Card(
                            margin: EdgeInsets.only(bottom: 8),
                            elevation: 2,
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.blue,
                                child: Icon(Icons.person, color: Colors.white),
                              ),
                              title: Text('${resultado['lider']['nombres']} ${resultado['lider']['apellidos']}'),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${resultado['tipo']}: ${resultado['nombre']}'),
                                  Text('Cédula: ${resultado['lider']['identificacion']}'),
                                  if (resultado['lider']['numero_celular'] != null)
                                    Text('Teléfono: ${resultado['lider']['numero_celular']}'),
                                ],
                              ),
                              isThreeLine: true,
                            ),
                          )).toList(),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Jerarquía completa por localidades
              Row(
                children: [
                  Icon(Icons.account_tree, color: Colors.green),
                  const SizedBox(width: 8),
                  Text(
                    'Jerarquía Completa por Localidades',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Localidades
              if (localidadesOrdenadas.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(Icons.info, color: Colors.blue),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'No hay localidades con líderes o votantes visibles en tu jurisdicción.',
                            style: TextStyle(color: Colors.blue.shade800),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ...localidadesOrdenadas.map((entry) {
                  return _buildLocalidadCard(entry.key, entry.value);
                }).toList(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLocalidadCard(String key, Map<String, dynamic> localidad) {
    final lideres = localidad['lideres'] as List<dynamic>? ?? [];
    final votantes = localidad['votantes'] as List<dynamic>? ?? [];
    final liderLocalidad = localidad['lider_localidad'] as Map<String, dynamic>?;
    final tipo = localidad['tipo'] ?? 'localidad';
    final nombre = localidad['nombre'] ?? 'Sin nombre';

    String tipoLabel = {
      'ciudad': '🏙️ Ciudad/Departamento',
      'municipio': '🏢 Municipio',
      'comuna': '🏠 Comuna',
      'puesto_votacion': '🗳️ Puesto de Votación',
    }[tipo] ?? '📍 Localidad';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ExpansionTile(
        title: Text(
          '$tipoLabel: $nombre',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Votantes: ${votantes.length}',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            if (liderLocalidad != null)
              Text(
                liderLocalidad['nombres'] == 'No tiene líder'
                    ? '👤 Líder: No asignado'
                    : '👤 Líder: ${liderLocalidad['nombres']} ${liderLocalidad['apellidos']} (${liderLocalidad['identificacion']})',
                style: TextStyle(
                  color: liderLocalidad['nombres'] == 'No tiene líder' ? Colors.orange : Colors.blue,
                  fontSize: 12,
                ),
              ),
          ],
        ),
        children: [
          // Mostrar información del líder de localidad
          if (liderLocalidad != null) ...[
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: liderLocalidad['nombres'] == 'No tiene líder' 
                    ? Colors.orange.shade50 
                    : Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: liderLocalidad['nombres'] == 'No tiene líder' 
                      ? Colors.orange.shade200 
                      : Colors.blue.shade200,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    liderLocalidad['nombres'] == 'No tiene líder' 
                        ? Icons.person_off 
                        : Icons.person_pin,
                    color: liderLocalidad['nombres'] == 'No tiene líder' 
                        ? Colors.orange 
                        : Colors.blue,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          liderLocalidad['nombres'] == 'No tiene líder'
                              ? 'Esta localidad no tiene líder asignado'
                              : 'Líder de ${_getTipoLocalidadLabel(tipo)}: ${liderLocalidad['nombres']} ${liderLocalidad['apellidos']}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: liderLocalidad['nombres'] == 'No tiene líder' 
                                ? Colors.orange.shade800 
                                : Colors.blue.shade800,
                          ),
                        ),
                        if (liderLocalidad['nombres'] != 'No tiene líder') ...[
                          Text('Cédula: ${liderLocalidad['identificacion']}'),
                          if (liderLocalidad['numero_celular'] != null && liderLocalidad['numero_celular'].toString().isNotEmpty)
                            Text('📱 ${liderLocalidad['numero_celular']}'),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          
          // Mostrar votantes si existen
          if (votantes.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '👥 Votantes (${votantes.length})',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              ),
            ),
            ...votantes.map((votante) => _buildVotanteTile(votante)),
          ],
          
          if (votantes.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'No hay votantes en esta localidad.',
                style: TextStyle(color: Colors.grey),
              ),
            ),
        ],
      ),
    );
  }

  String _getTipoLocalidadLabel(String tipo) {
    return {
      'ciudad': 'Ciudad/Departamento',
      'municipio': 'Municipio',
      'comuna': 'Comuna',
      'puesto_votacion': 'Puesto de Votación',
    }[tipo] ?? 'Localidad';
  }

  Widget _buildLiderTile(Map<String, dynamic> lider) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Colors.blue,
        child: Text(
          lider['nombres']?.substring(0, 1).toUpperCase() ?? 'L',
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ),
      title: Text(
        '${lider['nombres']} ${lider['apellidos']}',
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Cédula: ${lider['identificacion']}'),
          if (lider['numero_celular'] != null && lider['numero_celular'].toString().isNotEmpty)
            Text('📱 ${lider['numero_celular']}'),
          if (lider['email'] != null && lider['email'].toString().isNotEmpty)
            Text('📧 ${lider['email']}'),
          Text(
            'Nivel: ${_getNivelJefeLabel(lider['nivel_jefe'])}',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.blue,
            ),
          ),
        ],
      ),
      isThreeLine: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 4),
    );
  }

  Widget _buildVotanteTile(Map<String, dynamic> votante) {
    final liderDirecto = votante['lider_directo'];
    
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Colors.green,
        child: Text(
          votante['nombres']?.substring(0, 1).toUpperCase() ?? 'V',
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ),
      title: Text(
        '${votante['nombres']} ${votante['apellidos']}',
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Cédula: ${votante['identificacion']}'),
          if (votante['numero_celular'] != null && votante['numero_celular'].toString().isNotEmpty)
            Text('📱 ${votante['numero_celular']}'),
          if (votante['pertenencia'] != null && votante['pertenencia'].toString().isNotEmpty)
            Text('Rol: ${votante['pertenencia']}'),
          if (liderDirecto != null)
            Text(
              '👤 Líder: ${liderDirecto['nombres']} ${liderDirecto['apellidos']} (${liderDirecto['identificacion']})',
              style: const TextStyle(
                fontStyle: FontStyle.italic,
                color: Colors.blue,
              ),
            ),
        ],
      ),
      isThreeLine: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 4),
    );
  }

  String _getNivelJefeLabel(String? nivel) {
    return {
      'departamental': 'Departamental',
      'municipal': 'Municipal',
      'comuna': 'Comunal',
      'puesto_votacion': 'Puesto de Votación',
    }[nivel] ?? 'No definido';
  }

  String _getUserLevelDescription(Map<String, dynamic> usuario) {
    if (usuario['es_candidato'] == true) {
      return 'Candidato (puedes ver toda la jerarquía)';
    } else if (usuario['es_jefe'] == true) {
      String nivel = '';
      switch (usuario['nivel_jefe']) {
        case 'departamental':
          nivel = 'Departamental';
          break;
        case 'municipal':
          nivel = 'Municipal';
          break;
        case 'comuna':
          nivel = 'Comuna';
          break;
        case 'puesto_votacion':
          nivel = 'Puesto de Votación';
          break;
        default:
          nivel = 'Jefe';
      }
      
      String ubicacion = '';
      if (usuario['jefe_ciudad_nombre'] != null) {
        ubicacion += ' de ${usuario['jefe_ciudad_nombre']}';
      }
      if (usuario['jefe_municipio_nombre'] != null) {
        ubicacion += ' - ${usuario['jefe_municipio_nombre']}';
      }
      if (usuario['jefe_comuna_nombre'] != null) {
        ubicacion += ' - ${usuario['jefe_comuna_nombre']}';
      }
      
      return '$nivel$ubicacion';
    } else {
      return 'Votante regular';
    }
  }



  // Convertir datos de jerarquía al formato esperado por localidad
  Map<String, dynamic> _convertToLocalidadFormat(
    List<Map<String, dynamic>> hierarchyData, 
    [String? filtroTipo, 
    int? filtroCiudadId, 
    int? filtroMunicipioId, 
    int? filtroComunaId]
  ) {
    final Map<String, Map<String, dynamic>> localidades = {};
    
    // Agrupar votantes por localidad
    for (final votante in hierarchyData) {
      final ciudadNombre = votante['ciudad_nombre']?.toString();
      final municipioNombre = votante['municipio_nombre']?.toString();
      final comunaNombre = votante['comuna_nombre']?.toString();
      final puestoVotacionNombre = votante['puesto_votacion_nombre']?.toString();
      
      // Aplicar filtros jerárquicos
      final ciudadId = votante['ciudad_id'];
      final municipioId = votante['municipio_id'];
      final comunaId = votante['comuna_id'];
      
      // Si hay filtros jerárquicos activos, aplicarlos
      if (filtroCiudadId != null && ciudadId != filtroCiudadId) continue;
      if (filtroMunicipioId != null && municipioId != filtroMunicipioId) continue;
      if (filtroComunaId != null && comunaId != filtroComunaId) continue;
      
      // Crear múltiples agrupaciones según el filtro o usar la más específica
      List<Map<String, String>> agrupaciones = [];
      
      if (filtroTipo == null || filtroTipo == 'todos') {
        // Sin filtro: usar la más específica disponible
        if (puestoVotacionNombre != null && puestoVotacionNombre.isNotEmpty) {
          agrupaciones.add({
            'key': 'puesto_${votante['puesto_votacion_id'] ?? 'unknown'}',
            'tipo': 'puesto_votacion',
            'nombre': puestoVotacionNombre,
            'ciudad': ciudadNombre ?? 'Sin ciudad',
            'municipio': municipioNombre ?? 'Sin municipio',
          });
        } else if (comunaNombre != null && comunaNombre.isNotEmpty) {
          agrupaciones.add({
            'key': 'comuna_${votante['comuna_id'] ?? 'unknown'}',
            'tipo': 'comuna',
            'nombre': comunaNombre,
            'ciudad': ciudadNombre ?? 'Sin ciudad',
            'municipio': municipioNombre ?? 'Sin municipio',
          });
        } else if (municipioNombre != null && municipioNombre.isNotEmpty) {
          agrupaciones.add({
            'key': 'municipio_${votante['municipio_id'] ?? 'unknown'}',
            'tipo': 'municipio',
            'nombre': municipioNombre,
            'ciudad': ciudadNombre ?? 'Sin ciudad',
            'municipio': municipioNombre,
          });
        } else if (ciudadNombre != null && ciudadNombre.isNotEmpty) {
          agrupaciones.add({
            'key': 'ciudad_${votante['ciudad_id'] ?? 'unknown'}',
            'tipo': 'ciudad',
            'nombre': ciudadNombre,
            'ciudad': ciudadNombre,
            'municipio': 'Sin municipio',
          });
        }
      } else {
        // Con filtro: agrupar según el tipo solicitado
        if (filtroTipo == 'puesto' && puestoVotacionNombre != null && puestoVotacionNombre.isNotEmpty) {
          agrupaciones.add({
            'key': 'puesto_${votante['puesto_votacion_id'] ?? 'unknown'}',
            'tipo': 'puesto_votacion',
            'nombre': puestoVotacionNombre,
            'ciudad': ciudadNombre ?? 'Sin ciudad',
            'municipio': municipioNombre ?? 'Sin municipio',
          });
        } else if (filtroTipo == 'comuna' && comunaNombre != null && comunaNombre.isNotEmpty) {
          agrupaciones.add({
            'key': 'comuna_${votante['comuna_id'] ?? 'unknown'}',
            'tipo': 'comuna',
            'nombre': comunaNombre,
            'ciudad': ciudadNombre ?? 'Sin ciudad',
            'municipio': municipioNombre ?? 'Sin municipio',
          });
        } else if (filtroTipo == 'municipio' && municipioNombre != null && municipioNombre.isNotEmpty) {
          agrupaciones.add({
            'key': 'municipio_${votante['municipio_id'] ?? 'unknown'}',
            'tipo': 'municipio',
            'nombre': municipioNombre,
            'ciudad': ciudadNombre ?? 'Sin ciudad',
            'municipio': municipioNombre,
          });
        } else if (filtroTipo == 'ciudad' && ciudadNombre != null && ciudadNombre.isNotEmpty) {
          agrupaciones.add({
            'key': 'ciudad_${votante['ciudad_id'] ?? 'unknown'}',
            'tipo': 'ciudad',
            'nombre': ciudadNombre,
            'ciudad': ciudadNombre,
            'municipio': 'Sin municipio',
          });
        }
      }
      
      // Si no hay agrupaciones válidas, crear una por defecto
      if (agrupaciones.isEmpty) {
        agrupaciones.add({
          'key': 'sin_localidad',
          'tipo': 'sin_localidad',
          'nombre': 'Sin localidad definida',
          'ciudad': 'Sin ciudad',
          'municipio': 'Sin municipio',
        });
      }
      
      // Agregar el votante a cada agrupación
      for (final agrupacion in agrupaciones) {
        final localidadKey = agrupacion['key']!;
        final tipoLocalidad = agrupacion['tipo']!;
        final nombreLocalidad = agrupacion['nombre']!;
        final ciudadFinal = agrupacion['ciudad']!;
        final municipioFinal = agrupacion['municipio']!;
        
        // Inicializar localidad si no existe
        if (!localidades.containsKey(localidadKey)) {
          localidades[localidadKey] = {
            'lideres': [],
          'votantes': [],
          'total_votantes': 0,
          'total_lideres': 0,
          'tipo': tipoLocalidad,
          'nombre': nombreLocalidad,
          'ciudad_nombre': ciudadFinal,
          'municipio_nombre': municipioFinal,
          'lider_localidad': {
            'nombres': 'No tiene líder',
            'apellidos': '',
            'identificacion': 'N/A',
            'nivel_jefe': null,
          },
        };
      }
      
      // Agregar votante a la localidad
      final localidad = localidades[localidadKey]!;
      final votantesList = localidad['votantes'] as List;
      
      // Crear estructura de votante compatible
      final votanteData = {
        'id': votante['id'],
        'identificacion': votante['identificacion'],
        'nombres': votante['nombres'],
        'apellidos': votante['apellidos'],
        'numero_celular': votante['numero_celular'],
        'email': votante['email'],
        'pertenencia': votante['pertenencia'] ?? '',
        'es_jefe': votante['es_jefe'] ?? false,
        'hierarchy_level': votante['hierarchy_level'] ?? 1,
        'lider_directo': {
          'nombres': 'En tu jerarquía',
          'apellidos': '',
          'identificacion': 'Nivel ${votante['hierarchy_level'] ?? 1}',
        },
      };
      
        votantesList.add(votanteData);
        localidad['total_votantes'] = votantesList.length;
      }
    }
    
    return {
      'localidades': localidades,
      'total_localidades': localidades.length,
      'total_votantes_jerarquia': hierarchyData.length,
      'jerarquia_completa': hierarchyData, // Agregar jerarquía completa para exportación
    };
  }

  // Widget para los filtros jerárquicos
  Widget _buildHierarchicalFilters(
    Map<String, dynamic> lookups,
    ValueNotifier<int?> filtroCiudad,
    ValueNotifier<int?> filtroMunicipio,
    ValueNotifier<int?> filtroComuna,
  ) {
    final ciudades = (lookups['ciudades'] as List?) ?? [];
    final municipios = (lookups['municipios'] as List?)?.where((m) => 
      filtroCiudad.value == null || m['ciudad_id'] == filtroCiudad.value
    ).toList() ?? [];
    final comunas = (lookups['comunas'] as List?)?.where((c) => 
      filtroMunicipio.value == null || c['municipio_id'] == filtroMunicipio.value
    ).toList() ?? [];

    return Card(
      color: Colors.purple.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.filter_alt, color: Colors.purple.shade700),
                const SizedBox(width: 8),
                Text(
                  'Filtros Jerárquicos de Localidad',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.purple.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Filtra las localidades de forma jerárquica: Ciudad → Municipio → Comuna',
              style: TextStyle(
                fontSize: 12,
                color: Colors.purple.shade600,
              ),
            ),
            const SizedBox(height: 16),
            
            // Filtro por Ciudad
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: filtroCiudad.value,
                    decoration: InputDecoration(
                      labelText: '🏙️ Filtrar por Ciudad',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: [
                      const DropdownMenuItem<int>(
                        value: null,
                        child: Text('Todas las ciudades'),
                      ),
                      ...ciudades.map<DropdownMenuItem<int>>((ciudad) => 
                        DropdownMenuItem<int>(
                          value: ciudad['id'] as int,
                          child: Text(ciudad['nombre'] as String),
                        )
                      ).toList(),
                    ],
                    onChanged: (value) {
                      filtroCiudad.value = value;
                      // Limpiar filtros dependientes
                      filtroMunicipio.value = null;
                      filtroComuna.value = null;
                    },
                  ),
                ),
                const SizedBox(width: 8),
                if (filtroCiudad.value != null)
                  IconButton(
                    onPressed: () {
                      filtroCiudad.value = null;
                      filtroMunicipio.value = null;
                      filtroComuna.value = null;
                    },
                    icon: const Icon(Icons.clear),
                    tooltip: 'Limpiar filtro de ciudad',
                  ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // Filtro por Municipio (solo si hay ciudad seleccionada)
            if (filtroCiudad.value != null) ...[
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: filtroMunicipio.value,
                      decoration: InputDecoration(
                        labelText: '🏢 Filtrar por Municipio',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      items: [
                        const DropdownMenuItem<int>(
                          value: null,
                          child: Text('Todos los municipios'),
                        ),
                        ...municipios.map<DropdownMenuItem<int>>((municipio) => 
                          DropdownMenuItem<int>(
                            value: municipio['id'] as int,
                            child: Text(municipio['nombre'] as String),
                          )
                        ).toList(),
                      ],
                      onChanged: (value) {
                        filtroMunicipio.value = value;
                        // Limpiar filtros dependientes
                        filtroComuna.value = null;
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (filtroMunicipio.value != null)
                    IconButton(
                      onPressed: () {
                        filtroMunicipio.value = null;
                        filtroComuna.value = null;
                      },
                      icon: const Icon(Icons.clear),
                      tooltip: 'Limpiar filtro de municipio',
                    ),
                ],
              ),
              
              const SizedBox(height: 12),
            ],
            
            // Filtro por Comuna (solo si hay municipio seleccionado)
            if (filtroMunicipio.value != null) ...[
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: filtroComuna.value,
                      decoration: InputDecoration(
                        labelText: '🏠 Filtrar por Comuna',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      items: [
                        const DropdownMenuItem<int>(
                          value: null,
                          child: Text('Todas las comunas'),
                        ),
                        ...comunas.map<DropdownMenuItem<int>>((comuna) => 
                          DropdownMenuItem<int>(
                            value: comuna['id'] as int,
                            child: Text(comuna['nombre'] as String),
                          )
                        ).toList(),
                      ],
                      onChanged: (value) {
                        filtroComuna.value = value;
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (filtroComuna.value != null)
                    IconButton(
                      onPressed: () {
                        filtroComuna.value = null;
                      },
                      icon: const Icon(Icons.clear),
                      tooltip: 'Limpiar filtro de comuna',
                    ),
                ],
              ),
            ],
            
            // Información de filtros activos
            if (filtroCiudad.value != null || filtroMunicipio.value != null || filtroComuna.value != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.purple.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.purple.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.purple.shade700, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _getActiveFiltersText(lookups, filtroCiudad.value, filtroMunicipio.value, filtroComuna.value),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.purple.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _getActiveFiltersText(Map<String, dynamic> lookups, int? ciudadId, int? municipioId, int? comunaId) {
    final List<String> filtros = [];
    
    if (ciudadId != null) {
      final ciudades = (lookups['ciudades'] as List?) ?? [];
      final ciudad = ciudades.firstWhere((c) => c['id'] == ciudadId, orElse: () => null);
      if (ciudad != null) {
        filtros.add('Ciudad: ${ciudad['nombre']}');
      }
    }
    
    if (municipioId != null) {
      final municipios = (lookups['municipios'] as List?) ?? [];
      final municipio = municipios.firstWhere((m) => m['id'] == municipioId, orElse: () => null);
      if (municipio != null) {
        filtros.add('Municipio: ${municipio['nombre']}');
      }
    }
    
    if (comunaId != null) {
      final comunas = (lookups['comunas'] as List?) ?? [];
      final comuna = comunas.firstWhere((c) => c['id'] == comunaId, orElse: () => null);
      if (comuna != null) {
        filtros.add('Comuna: ${comuna['nombre']}');
      }
    }
    
    if (filtros.isEmpty) return 'Sin filtros activos';
    return 'Filtros activos: ${filtros.join(' → ')}';
  }

  // Widget para los chips de filtro
  Widget _buildFiltroChip(String valor, String label, ValueNotifier<String> filtroActual) {
    final isSelected = filtroActual.value == valor;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          filtroActual.value = valor;
        }
      },
      selectedColor: Colors.green.shade200,
      checkmarkColor: Colors.green.shade700,
    );
  }
}