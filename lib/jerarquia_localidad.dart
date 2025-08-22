import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'main.dart';

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

    // Cargar datos iniciales
    useEffect(() {
      _loadJerarquia() async {
        try {
          final data = await api.jerarquiaLocalidad(candidaturaId);
          jerarquiaData.value = data;
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

    // Ordenar localidades por tipo y nombre
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
            final data = await api.jerarquiaLocalidad(candidaturaId);
            jerarquiaData.value = data;
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
                      Text(
                        'Usuario Actual',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text('👤 ${usuarioActual['nombres']} ${usuarioActual['apellidos']} (${usuarioActual['identificacion']})'),
                      Text('Nivel: ${_getNivelJefeLabel(usuarioActual['nivel_jefe'])}'),
                      if (usuarioActual['jefe_ciudad_nombre'] != null)
                        Text('Jurisdicción: ${usuarioActual['jefe_ciudad_nombre']}'),
                      const SizedBox(height: 8),
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
}