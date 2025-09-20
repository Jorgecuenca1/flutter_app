import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../main.dart';

class MapVotantesScreen extends ConsumerStatefulWidget {
  const MapVotantesScreen({super.key, required this.candId, required this.candName});
  final String candId;
  final String candName;

  @override
  ConsumerState<MapVotantesScreen> createState() => _MapVotantesScreenState();
}

class _MapVotantesScreenState extends ConsumerState<MapVotantesScreen> {
  final MapController _mapController = MapController();
  List<Marker> _markers = [];
  List<Map<String, dynamic>> _votantes = [];
  bool _loading = true;
  String? _selectedFilter;
  
  // Posición inicial del mapa (Colombia)
  static const LatLng _initialPosition = LatLng(4.570868, -74.297333);

  @override
  void initState() {
    super.initState();
    _loadVotantesWithLocation();
  }

  Future<void> _loadVotantesWithLocation() async {
    try {
      setState(() => _loading = true);
      
      final api = ref.read(apiProvider);
      final response = await api.getJson('/api/candidaturas/${widget.candId}/votantes/');
      final votantes = response['votantes'] as List? ?? [];
      
      // Filtrar solo votantes con ubicación
      final votantesConUbicacion = votantes.where((v) {
        final ubicacion = v['ubicacion'];
        return ubicacion != null && 
               ubicacion['latitud'] != null && 
               ubicacion['longitud'] != null;
      }).toList();
      
      setState(() {
        _votantes = List<Map<String, dynamic>>.from(votantesConUbicacion);
        _createMarkers();
        _loading = false;
      });
      
      // Centrar el mapa en el primer votante si existe
      if (votantesConUbicacion.isNotEmpty) {
        final firstVotante = votantesConUbicacion.first;
        final ubicacion = firstVotante['ubicacion'];
        _mapController.move(
          LatLng(
            ubicacion['latitud'].toDouble(),
            ubicacion['longitud'].toDouble(),
          ),
          14,
        );
      }
    } catch (e) {
      print('Error cargando votantes: $e');
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error cargando votantes: $e')),
        );
      }
    }
  }

  void _createMarkers() {
    _markers.clear();
    
    for (final votante in _votantes) {
      // Aplicar filtro si está seleccionado
      if (_selectedFilter != null && votante['pertenencia'] != _selectedFilter) {
        continue;
      }
      
      final ubicacion = votante['ubicacion'];
      if (ubicacion == null) continue;
      
      final lat = ubicacion['latitud']?.toDouble();
      final lng = ubicacion['longitud']?.toDouble();
      
      if (lat == null || lng == null) continue;
      
      final marker = Marker(
        point: LatLng(lat, lng),
        width: 40,
        height: 40,
        child: GestureDetector(
          onTap: () => _showVotanteDetails(votante),
          child: Icon(
            Icons.location_on,
            color: _getMarkerColor(votante['pertenencia']),
            size: 40,
          ),
        ),
      );
      
      _markers.add(marker);
    }
  }

  Color _getMarkerColor(String? pertenencia) {
    switch (pertenencia?.toLowerCase()) {
      case 'delegado':
        return Colors.blue;
      case 'verificado':
        return Colors.green;
      case 'publicidad':
        return Colors.yellow;
      case 'logística':
      case 'logistica':
        return Colors.orange;
      case 'agendador':
        return Colors.purple;
      default:
        return Colors.red;
    }
  }

  void _showVotanteDetails(Map<String, dynamic> votante) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${votante['nombres']} ${votante['apellidos']}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.phone),
              title: Text(votante['numero_celular'] ?? 'Sin teléfono'),
              dense: true,
            ),
            ListTile(
              leading: const Icon(Icons.email),
              title: Text(votante['email'] ?? 'Sin email'),
              dense: true,
            ),
            ListTile(
              leading: const Icon(Icons.location_on),
              title: Text(votante['direccion'] ?? 'Sin dirección'),
              dense: true,
            ),
            if (votante['pertenencia'] != null)
              ListTile(
                leading: const Icon(Icons.badge),
                title: Text('Rol: ${votante['pertenencia']}'),
                dense: true,
              ),
            if (votante['ubicacion']?['timestamp'] != null)
              ListTile(
                leading: const Icon(Icons.access_time),
                title: Text('Actualizado: ${votante['ubicacion']['timestamp']}'),
                dense: true,
              ),
          ],
        ),
      ),
    );
  }

  void _showFilterDialog() {
    final roles = ['Delegado', 'Verificado', 'Publicidad', 'Logística', 'Agendador'];
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Filtrar por rol'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Todos'),
              leading: Radio<String?>(
                value: null,
                groupValue: _selectedFilter,
                onChanged: (value) {
                  setState(() {
                    _selectedFilter = value;
                    _createMarkers();
                  });
                  Navigator.pop(context);
                },
              ),
            ),
            ...roles.map((role) => ListTile(
              title: Text(role),
              leading: Radio<String?>(
                value: role,
                groupValue: _selectedFilter,
                onChanged: (value) {
                  setState(() {
                    _selectedFilter = value;
                    _createMarkers();
                  });
                  Navigator.pop(context);
                },
              ),
            )),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Mapa de Votantes - ${widget.candName}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadVotantesWithLocation,
          ),
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterDialog,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _initialPosition,
                    initialZoom: 6,
                    minZoom: 3,
                    maxZoom: 18,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.mivoto.app',
                    ),
                    MarkerLayer(
                      markers: _markers,
                    ),
                  ],
                ),
                Positioned(
                  top: 16,
                  left: 16,
                  right: 16,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Votantes con ubicación: ${_markers.length}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: [
                              _buildLegendItem('Delegado', Colors.blue),
                              _buildLegendItem('Verificado', Colors.green),
                              _buildLegendItem('Publicidad', Colors.yellow),
                              _buildLegendItem('Logística', Colors.orange),
                              _buildLegendItem('Agendador', Colors.purple),
                              _buildLegendItem('Otros', Colors.red),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.location_on, color: color, size: 16),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}