import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'main.dart';
import 'offline_app.dart';
import 'votante_detail.dart';

class ArbolScreen extends HookConsumerWidget {
  const ArbolScreen({super.key, required this.candId, required this.candName});
  final String candId;
  final String candName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hierarchyData = useState<List<Map<String, dynamic>>>([]);
    final userData = useState<Map<String, dynamic>?>(null);
    final isLoading = useState(true);
    final error = useState<String?>(null);
    final currentNodeId = useState<String?>(null); // ID del nodo actual
    final currentNodeName = useState<String>(''); // Nombre del nodo actual
    final navigationStack = useState<List<Map<String, String>>>([]); // Stack de navegación
    final currentChildren = useState<List<Map<String, dynamic>>>([]); // Hijos del nodo actual

    // Función para contar hijos directos
    int countDirectChildren(String nodeId, List<Map<String, dynamic>> allData) {
      int count = 0;
      for (final votante in allData) {
        final lideres = votante['lideres'];
        if (lideres != null && lideres is List && lideres.isNotEmpty) {
          final liderId = lideres.first.toString();
          if (liderId == nodeId) {
            count++;
          }
        }
      }
      return count;
    }

    // Función para cargar hijos de un nodo específico
    void loadChildrenForNode(String nodeId, List<Map<String, dynamic>> allData, ValueNotifier<List<Map<String, dynamic>>> childrenNotifier) {
      final children = <Map<String, dynamic>>[];
      
      for (final votante in allData) {
        final lideres = votante['lideres'];
        if (lideres != null && lideres is List && lideres.isNotEmpty) {
          final liderId = lideres.first.toString();
          if (liderId == nodeId) {
            // Calcular cuántos hijos directos tiene este votante
            final directChildren = countDirectChildren(votante['id'].toString(), allData);
            
            // Agregar información de contador
            final votanteWithCount = Map<String, dynamic>.from(votante);
            votanteWithCount['direct_children_count'] = directChildren;
            
            children.add(votanteWithCount);
          }
        }
      }
      
      // Ordenar por nombre
      children.sort((a, b) {
        final nameA = '${a['nombres'] ?? ''} ${a['apellidos'] ?? ''}'.trim();
        final nameB = '${b['nombres'] ?? ''} ${b['apellidos'] ?? ''}'.trim();
        return nameA.compareTo(nameB);
      });
      
      childrenNotifier.value = children;
    }

    // Función para cargar la jerarquía
    Future<void> loadHierarchy() async {
      isLoading.value = true;
      error.value = null;

      try {
        final api = ref.read(apiProvider);
        final storage = ref.read(storageProvider);
        
        // Obtener datos del usuario actual
        userData.value = await storage.getCachedUserData();
        if (userData.value == null) {
          userData.value = await api.me();
          await storage.cacheUserData(userData.value!);
        }
        
        final currentUserId = userData.value?['id']?.toString() ?? 
                             userData.value?['votante']?['id']?.toString();
        
        if (currentUserId == null) {
          throw Exception('No se pudo obtener el ID del usuario actual');
        }

        // Intentar cargar desde la API primero
        try {
          final allVotantes = await api.votantesList(candId);
          
          // Guardar en cache y calcular jerarquía
          await storage.cacheVotantesWithHierarchy(candId, allVotantes, currentUserId);
          hierarchyData.value = await storage.getVotantesHierarchy(candId, currentUserId);
        } catch (e) {
          // Si falla la API, usar datos locales
          hierarchyData.value = await storage.getVotantesHierarchy(candId, currentUserId);
        }

        // Inicializar con el nodo raíz (candidato)
        if (userData.value != null) {
          final userVotante = userData.value!['votante'] ?? userData.value!;
          currentNodeId.value = currentUserId;
          currentNodeName.value = '${userVotante['nombres'] ?? ''} ${userVotante['apellidos'] ?? ''}'.trim();
          
          // Limpiar stack de navegación
          navigationStack.value = [];
          
          // Cargar hijos directos del candidato
          loadChildrenForNode(currentUserId, hierarchyData.value, currentChildren);
        }

      } catch (e) {
        error.value = e.toString();
      } finally {
        isLoading.value = false;
      }
    }

    // Función para navegar a un nodo hijo
    void navigateToNode(Map<String, dynamic> nodeData) {
      final nodeId = nodeData['id'].toString();
      final nodeName = '${nodeData['nombres'] ?? ''} ${nodeData['apellidos'] ?? ''}'.trim();
      
      // Agregar nodo actual al stack de navegación
      navigationStack.value = [
        ...navigationStack.value,
        {
          'id': currentNodeId.value ?? '',
          'name': currentNodeName.value,
        }
      ];
      
      // Actualizar nodo actual
      currentNodeId.value = nodeId;
      currentNodeName.value = nodeName;
      
      // Cargar hijos del nuevo nodo
      loadChildrenForNode(nodeId, hierarchyData.value, currentChildren);
    }

    // Función para retroceder en la navegación
    void navigateBack() {
      if (navigationStack.value.isNotEmpty) {
        final previousNode = navigationStack.value.last;
        
        // Remover último elemento del stack
        navigationStack.value = navigationStack.value.sublist(0, navigationStack.value.length - 1);
        
        // Actualizar nodo actual
        currentNodeId.value = previousNode['id'];
        currentNodeName.value = previousNode['name'] ?? '';
        
        // Cargar hijos del nodo anterior
        loadChildrenForNode(previousNode['id'] ?? '', hierarchyData.value, currentChildren);
      }
    }

    // Cargar datos al inicializar
    useEffect(() {
      loadHierarchy();
      return null;
    }, []);

    return Scaffold(
      appBar: AppBar(
        title: Text('Árbol - $candName'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: loadHierarchy,
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: _buildBody(
        context,
        isLoading.value,
        error.value,
        currentNodeName.value,
        currentChildren.value,
        navigationStack.value,
        navigateToNode,
        navigateBack,
        candId,
        candName,
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    bool isLoading,
    String? error,
    String currentNodeName,
    List<Map<String, dynamic>> currentChildren,
    List<Map<String, String>> navigationStack,
    Function(Map<String, dynamic>) navigateToNode,
    VoidCallback navigateBack,
    String candId,
    String candName,
  ) {
    if (isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Cargando árbol jerárquico...'),
          ],
        ),
      );
    }

    if (error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text('Error: $error'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                // Trigger reload
              },
              child: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Header con información del nodo actual
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Breadcrumb de navegación
              if (navigationStack.isNotEmpty) ...[
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (int i = 0; i < navigationStack.length; i++) ...[
                        GestureDetector(
                          onTap: () {
                            // Navegar directamente a este nivel
                            // Implementar navegación directa si es necesario
                          },
                          child: Text(
                            navigationStack[i]['name'] ?? '',
                            style: TextStyle(
                              color: Colors.blue[600],
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                        const Icon(Icons.chevron_right, size: 16),
                      ],
                      Text(
                        currentNodeName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
              
              // Información del nodo actual
              Row(
                children: [
                  Icon(
                    navigationStack.isEmpty ? Icons.account_circle : Icons.person,
                    color: Theme.of(context).primaryColor,
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      currentNodeName.isEmpty ? 'Nodo Raíz' : currentNodeName,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (navigationStack.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: navigateBack,
                      tooltip: 'Volver',
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                currentChildren.isEmpty 
                    ? 'No tiene votantes directos'
                    : '${currentChildren.length} votantes directos',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
        
        // Carrusel vertical de votantes
        Expanded(
          child: currentChildren.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.people_outline, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text('Este nodo no tiene votantes directos'),
                      SizedBox(height: 8),
                      Text(
                        'Los votantes agregados por este usuario aparecerán aquí',
                        style: TextStyle(color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : _buildVerticalCarousel(context, currentChildren, navigateToNode, candId, candName),
        ),
      ],
    );
  }

  Widget _buildVerticalCarousel(
    BuildContext context,
    List<Map<String, dynamic>> children,
    Function(Map<String, dynamic>) navigateToNode,
    String candId,
    String candName,
  ) {
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: children.length,
      itemBuilder: (context, index) {
        final votante = children[index];
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: _buildVotanteExpansionTile(context, votante, navigateToNode, candId, candName),
        );
      },
    );
  }

  Widget _buildVotanteExpansionTile(
    BuildContext context,
    Map<String, dynamic> votante,
    Function(Map<String, dynamic>) navigateToNode,
    String candId,
    String candName,
  ) {
    final nombres = votante['nombres']?.toString() ?? 'Sin nombre';
    final apellidos = votante['apellidos']?.toString() ?? 'Sin apellido';
    final identificacion = votante['identificacion']?.toString() ?? 'Sin ID';
    final esJefe = votante['es_jefe'] == true;
    final pertenencia = votante['pertenencia']?.toString() ?? '';
    final nivelJefe = votante['nivel_jefe']?.toString() ?? '';
    final directChildrenCount = votante['direct_children_count'] ?? 0;
    
    // Información de localidad
    final ciudadNombre = votante['ciudad_nombre']?.toString() ?? '';
    final municipioNombre = votante['municipio_nombre']?.toString() ?? '';
    final comunaNombre = votante['comuna_nombre']?.toString() ?? '';
    final puestoVotacionNombre = votante['puesto_votacion_nombre']?.toString() ?? '';

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: ExpansionTile(
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
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: directChildrenCount > 0 ? Colors.green : Colors.grey[400],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$directChildrenCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        subtitle: Text(
          '📱 $identificacion',
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 14,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (directChildrenCount > 0)
              IconButton(
                icon: const Icon(Icons.account_tree, color: Colors.blue),
                onPressed: () => navigateToNode(votante),
                tooltip: 'Explorar jerarquía',
              ),
            IconButton(
              icon: const Icon(Icons.person, color: Colors.green),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => VotanteDetailScreen(
                      candId: candId,
                      candName: candName,
                      votanteId: votante['id']?.toString() ?? '',
                    ),
                  ),
                );
              },
              tooltip: 'Ver detalles',
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Información básica
                if (pertenencia.isNotEmpty) 
                  _buildInfoRow(Icons.label, 'Pertenencia: $pertenencia'),
                if (esJefe && nivelJefe.isNotEmpty) 
                  _buildInfoRow(Icons.star, 'Jefe Nivel: $nivelJefe'),
                
                const SizedBox(height: 8),
                
                // Información de localidad
                if (ciudadNombre.isNotEmpty || municipioNombre.isNotEmpty || comunaNombre.isNotEmpty) ...[
                  const Divider(),
                  const SizedBox(height: 8),
                  Text(
                    'Ubicación:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (ciudadNombre.isNotEmpty)
                    _buildInfoRow(Icons.location_city, 'Ciudad: $ciudadNombre'),
                  if (municipioNombre.isNotEmpty)
                    _buildInfoRow(Icons.location_on, 'Municipio: $municipioNombre'),
                  if (comunaNombre.isNotEmpty)
                    _buildInfoRow(Icons.place, 'Comuna: $comunaNombre'),
                  if (puestoVotacionNombre.isNotEmpty)
                    _buildInfoRow(Icons.how_to_vote, 'Puesto: $puestoVotacionNombre'),
                ],
                
                const SizedBox(height: 16),
                
                // Botones de acción
                Row(
                  children: [
                    if (directChildrenCount > 0) ...[
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => navigateToNode(votante),
                          icon: const Icon(Icons.account_tree),
                          label: Text('Explorar ($directChildrenCount)'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => VotanteDetailScreen(
                                candId: candId,
                                candName: candName,
                                votanteId: votante['id']?.toString() ?? '',
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.person),
                        label: const Text('Ver Detalles'),
                      ),
                    ),
                  ],
                ),
                
                if (directChildrenCount == 0)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.grey[600], size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Este votante no tiene subordinados',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    if (text.isEmpty) return const SizedBox.shrink();
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[700],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
