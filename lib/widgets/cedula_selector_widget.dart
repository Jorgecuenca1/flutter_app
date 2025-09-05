import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import '../main.dart';
import '../offline_app.dart';

class CedulaSelectorWidget extends HookConsumerWidget {
  final TextEditingController controller;
  final String candidaturaId;
  final String labelText;
  final String hintText;
  final Function(Map<String, dynamic>)? onVotanteSelected;

  const CedulaSelectorWidget({
    Key? key,
    required this.controller,
    required this.candidaturaId,
    this.labelText = 'Cédula del Encargado',
    this.hintText = 'Buscar por cédula o nombre...',
    this.onVotanteSelected,
  }) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchController = useTextEditingController();
    final votantesDisponibles = useState<List<Map<String, dynamic>>>([]);
    final votantesFiltrados = useState<List<Map<String, dynamic>>>([]);
    final isLoading = useState(false);
    final showDropdown = useState(false);
    final selectedVotante = useState<Map<String, dynamic>?>(null);

    // Cargar votantes disponibles
    Future<void> loadVotantes() async {
      isLoading.value = true;
      try {
        final api = ref.read(apiProvider);
        final storage = ref.read(storageProvider);
        
        // Obtener datos del usuario actual
        final userData = await storage.getCachedUserData() ?? await api.me();
        final currentUserId = userData['id']?.toString() ?? userData['votante']?['id']?.toString();
        
        if (currentUserId != null) {
          // Intentar cargar desde la API primero
          try {
            final allVotantes = await api.votantesList(candidaturaId);
            await storage.cacheVotantesWithHierarchy(candidaturaId, allVotantes, currentUserId);
            votantesDisponibles.value = await storage.getVotantesHierarchy(candidaturaId, currentUserId);
          } catch (e) {
            // Si falla la API, usar datos locales
            votantesDisponibles.value = await storage.getVotantesHierarchy(candidaturaId, currentUserId);
          }
        }
      } catch (e) {
        print('Error cargando votantes: $e');
      } finally {
        isLoading.value = false;
      }
    }

    // Filtrar votantes según la búsqueda
    void filterVotantes(String query) {
      if (query.trim().isEmpty) {
        votantesFiltrados.value = [];
        showDropdown.value = false;
        return;
      }

      final filtered = votantesDisponibles.value.where((votante) {
        final identificacion = votante['identificacion']?.toString().toLowerCase() ?? '';
        final nombres = votante['nombres']?.toString().toLowerCase() ?? '';
        final apellidos = votante['apellidos']?.toString().toLowerCase() ?? '';
        final searchTerm = query.toLowerCase();
        
        return identificacion.contains(searchTerm) || 
               nombres.contains(searchTerm) || 
               apellidos.contains(searchTerm);
      }).toList();

      // Ordenar por relevancia (primero por identificación exacta, luego por nombres)
      filtered.sort((a, b) {
        final aId = a['identificacion']?.toString().toLowerCase() ?? '';
        final bId = b['identificacion']?.toString().toLowerCase() ?? '';
        final queryLower = query.toLowerCase();
        
        // Priorizar coincidencias exactas de identificación
        if (aId == queryLower && bId != queryLower) return -1;
        if (bId == queryLower && aId != queryLower) return 1;
        
        // Luego por coincidencias que empiecen con la búsqueda
        if (aId.startsWith(queryLower) && !bId.startsWith(queryLower)) return -1;
        if (bId.startsWith(queryLower) && !aId.startsWith(queryLower)) return 1;
        
        // Finalmente orden alfabético por nombre
        final aNombre = '${a['nombres'] ?? ''} ${a['apellidos'] ?? ''}'.trim();
        final bNombre = '${b['nombres'] ?? ''} ${b['apellidos'] ?? ''}'.trim();
        return aNombre.compareTo(bNombre);
      });

      votantesFiltrados.value = filtered.take(10).toList(); // Limitar a 10 resultados
      showDropdown.value = filtered.isNotEmpty;
    }

    // Seleccionar un votante
    void selectVotante(Map<String, dynamic> votante) {
      selectedVotante.value = votante;
      controller.text = votante['identificacion']?.toString() ?? '';
      searchController.text = '${votante['nombres'] ?? ''} ${votante['apellidos'] ?? ''} (${votante['identificacion'] ?? ''})';
      showDropdown.value = false;
      onVotanteSelected?.call(votante);
    }

    // Limpiar selección
    void clearSelection() {
      selectedVotante.value = null;
      controller.clear();
      searchController.clear();
      showDropdown.value = false;
      votantesFiltrados.value = [];
    }

    // Cargar votantes al inicializar
    useEffect(() {
      loadVotantes();
      return null;
    }, []);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Campo de búsqueda
        TextField(
          controller: searchController,
          decoration: InputDecoration(
            labelText: labelText,
            hintText: hintText,
            prefixIcon: const Icon(Icons.search),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isLoading.value)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (selectedVotante.value != null)
                  Icon(Icons.check_circle, color: Colors.green[600])
                else if (searchController.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: clearSelection,
                    tooltip: 'Limpiar',
                  ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: loadVotantes,
                  tooltip: 'Actualizar lista',
                ),
              ],
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onChanged: filterVotantes,
          onTap: () {
            if (votantesFiltrados.value.isNotEmpty) {
              showDropdown.value = true;
            }
          },
        ),

        // Información del votante seleccionado
        if (selectedVotante.value != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green[200]!),
            ),
            child: Row(
              children: [
                Icon(Icons.person_pin, color: Colors.green[600]),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '✅ Encargado seleccionado:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.green[800],
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        '${selectedVotante.value!['nombres'] ?? ''} ${selectedVotante.value!['apellidos'] ?? ''}',
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      Text(
                        'Cédula: ${selectedVotante.value!['identificacion'] ?? ''}',
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                      if (selectedVotante.value!['numero_celular'] != null && 
                          selectedVotante.value!['numero_celular'].toString().isNotEmpty)
                        Text(
                          'Teléfono: ${selectedVotante.value!['numero_celular']}',
                          style: TextStyle(color: Colors.grey[600], fontSize: 12),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: clearSelection,
                  tooltip: 'Cambiar encargado',
                ),
              ],
            ),
          ),
        ],

        // Dropdown con resultados de búsqueda
        if (showDropdown.value && votantesFiltrados.value.isNotEmpty) ...[
          const SizedBox(height: 4),
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(8),
              color: Colors.white,
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: votantesFiltrados.value.length,
              itemBuilder: (context, index) {
                final votante = votantesFiltrados.value[index];
                final nombres = '${votante['nombres'] ?? ''} ${votante['apellidos'] ?? ''}'.trim();
                final identificacion = votante['identificacion']?.toString() ?? '';
                final celular = votante['numero_celular']?.toString() ?? '';
                final nivel = votante['hierarchy_level'] ?? 0;
                final esJefe = votante['es_jefe'] == true;

                return ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: esJefe ? Colors.orange[100] : Colors.blue[100],
                    child: Icon(
                      esJefe ? Icons.star : Icons.person,
                      size: 16,
                      color: esJefe ? Colors.orange[700] : Colors.blue[700],
                    ),
                  ),
                  title: Text(
                    nombres,
                    style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('📱 $identificacion', style: const TextStyle(fontSize: 12)),
                      if (celular.isNotEmpty)
                        Text('☎️ $celular', style: const TextStyle(fontSize: 11)),
                      Text(
                        '🌳 Nivel $nivel${esJefe ? ' (Jefe)' : ''}',
                        style: TextStyle(
                          fontSize: 11,
                          color: esJefe ? Colors.orange[700] : Colors.blue[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  onTap: () => selectVotante(votante),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                );
              },
            ),
          ),
        ],

        // Mensaje cuando no hay resultados
        if (showDropdown.value && votantesFiltrados.value.isEmpty && searchController.text.isNotEmpty) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange[200]!),
            ),
            child: Row(
              children: [
                Icon(Icons.warning, color: Colors.orange[600]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'No se encontraron votantes con "${searchController.text}" en tu jerarquía.',
                    style: TextStyle(color: Colors.orange[800], fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],

        // Información de ayuda
        if (votantesDisponibles.value.isNotEmpty && selectedVotante.value == null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue[600], size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '💡 Tienes ${votantesDisponibles.value.length} votantes disponibles. Escribe para buscar por cédula o nombre.',
                    style: TextStyle(color: Colors.blue[700], fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
