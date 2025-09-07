import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import '../offline_app.dart';
import '../main.dart';

class RoleSpecificSelectorWidget extends HookConsumerWidget {
  final String candidaturaId;
  final String roleFilter; // 'delegado', 'verificado', 'logistica'
  final String labelText;
  final String? hintText;
  final Function(Map<String, dynamic>) onVotanteSelected;

  const RoleSpecificSelectorWidget({
    super.key,
    required this.candidaturaId,
    required this.roleFilter,
    required this.labelText,
    this.hintText,
    required this.onVotanteSelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchController = useTextEditingController();
    final searchQuery = useState('');
    final votantes = useState<List<Map<String, dynamic>>>([]);
    final isLoading = useState(false);
    final selectedVotante = useState<Map<String, dynamic>?>(null);

    // Cargar votantes por rol
    Future<void> loadVotantesByRole() async {
      if (isLoading.value) return;
      
      isLoading.value = true;
      try {
        final api = ref.read(apiProvider);
        final response = await api.getVotantesPorRol(candidaturaId, roleFilter);
        votantes.value = response;
      } catch (e) {
        print('Error cargando votantes por rol: $e');
        votantes.value = [];
      } finally {
        isLoading.value = false;
      }
    }

    // Filtrar votantes por búsqueda
    List<Map<String, dynamic>> getFilteredVotantes() {
      if (searchQuery.value.isEmpty) {
        return votantes.value;
      }
      
      return votantes.value.where((votante) {
        final nombre = (votante['nombre'] ?? '').toString().toLowerCase();
        final identificacion = (votante['identificacion'] ?? '').toString().toLowerCase();
        final query = searchQuery.value.toLowerCase();
        
        return nombre.contains(query) || identificacion.contains(query);
      }).toList();
    }

    // Cargar datos al inicializar
    useEffect(() {
      loadVotantesByRole();
      return null;
    }, []);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Campo de búsqueda
        TextFormField(
          controller: searchController,
          decoration: InputDecoration(
            labelText: labelText,
            hintText: hintText ?? 'Buscar por nombre o cédula...',
            prefixIcon: const Icon(Icons.search),
            border: const OutlineInputBorder(),
          ),
          onChanged: (value) {
            searchQuery.value = value;
          },
        ),
        
        const SizedBox(height: 16),
        
        // Lista de votantes
        if (isLoading.value)
          const Center(child: CircularProgressIndicator())
        else if (votantes.value.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Icon(Icons.person_off, size: 48, color: Colors.grey[400]),
                const SizedBox(height: 8),
                Text(
                  'No hay votantes con rol: ${_getRoleDisplayName(roleFilter)}',
                  style: TextStyle(color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          )
        else
          Container(
            height: 300,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListView.builder(
              itemCount: getFilteredVotantes().length,
              itemBuilder: (context, index) {
                final votante = getFilteredVotantes()[index];
                final isSelected = selectedVotante.value?['id'] == votante['id'];
                
                return ListTile(
                  selected: isSelected,
                  leading: CircleAvatar(
                    backgroundColor: isSelected ? Colors.blue : Colors.grey[300],
                    child: Icon(
                      _getRoleIcon(roleFilter),
                      color: isSelected ? Colors.white : Colors.grey[600],
                    ),
                  ),
                  title: Text(
                    votante['nombre'] ?? 'Sin nombre',
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Cédula: ${votante['identificacion'] ?? 'N/A'}'),
                      if (votante['celular'] != null)
                        Text('Tel: ${votante['celular']}'),
                      Text(
                        'Rol: ${_getRoleDisplayName(roleFilter)}',
                        style: TextStyle(
                          color: Colors.blue[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  onTap: () {
                    selectedVotante.value = votante;
                    onVotanteSelected(votante);
                  },
                );
              },
            ),
          ),
        
        if (getFilteredVotantes().isEmpty && searchQuery.value.isNotEmpty && !isLoading.value)
          Container(
            padding: const EdgeInsets.all(16),
            child: Text(
              'No se encontraron votantes que coincidan con "${searchQuery.value}"',
              style: TextStyle(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }

  String _getRoleDisplayName(String role) {
    switch (role) {
      case 'delegado': return 'Delegado';
      case 'verificado': return 'Verificador';
      case 'logistica': return 'Logística';
      default: return role;
    }
  }

  IconData _getRoleIcon(String role) {
    switch (role) {
      case 'delegado': return Icons.how_to_vote;
      case 'verificado': return Icons.verified;
      case 'logistica': return Icons.local_shipping;
      default: return Icons.person;
    }
  }
}
