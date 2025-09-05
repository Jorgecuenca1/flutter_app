import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import '../services/pdf_export_service.dart';
import '../offline_app.dart';

class ExportFilterWidget extends HookConsumerWidget {
  final String candidaturaId;
  final String candidaturaName;
  final List<Map<String, dynamic>> hierarchyData;
  final Map<String, dynamic> userData;
  final Function(String)? onFilterChanged;
  final Function(List<Map<String, dynamic>>)? onFilteredDataChanged;

  const ExportFilterWidget({
    Key? key,
    required this.candidaturaId,
    required this.candidaturaName,
    required this.hierarchyData,
    required this.userData,
    this.onFilterChanged,
    this.onFilteredDataChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filterController = useTextEditingController();
    final isExporting = useState(false);
    final filteredData = useState<List<Map<String, dynamic>>>(hierarchyData);
    final showFilterResults = useState(false);

    // Función para filtrar datos
    void _filterData(String query) {
      if (query.trim().isEmpty) {
        filteredData.value = hierarchyData;
        showFilterResults.value = false;
      } else {
        final filtered = hierarchyData.where((votante) {
          final identificacion = votante['identificacion']?.toString().toLowerCase() ?? '';
          final nombres = votante['nombres']?.toString().toLowerCase() ?? '';
          final apellidos = votante['apellidos']?.toString().toLowerCase() ?? '';
          final searchTerm = query.toLowerCase();
          
          return identificacion.contains(searchTerm) || 
                 nombres.contains(searchTerm) || 
                 apellidos.contains(searchTerm);
        }).toList();
        
        filteredData.value = filtered;
        showFilterResults.value = true;
      }
      
      // Notificar cambios
      onFilterChanged?.call(query);
      onFilteredDataChanged?.call(filteredData.value);
    }

    // Función para exportar PDF
    Future<void> _exportPdf({String? filtroIdentificacion}) async {
      isExporting.value = true;
      try {
        final storage = ref.read(storageProvider);
        final pdfService = PdfExportService(storage);
        
        final pdfBytes = await pdfService.generateHierarchyPdf(
          candidaturaId: candidaturaId,
          candidaturaName: candidaturaName,
          userData: userData,
          hierarchyData: filtroIdentificacion != null ? filteredData.value : hierarchyData,
          filtroIdentificacion: filtroIdentificacion,
        );
        
        final fileName = filtroIdentificacion != null 
            ? 'jerarquia_${candidaturaName}_filtro_${filtroIdentificacion}_${DateTime.now().millisecondsSinceEpoch}.pdf'
            : 'jerarquia_${candidaturaName}_completa_${DateTime.now().millisecondsSinceEpoch}.pdf';
        
        // Mostrar opciones de qué hacer con el PDF
        await _showPdfOptionsDialog(context, pdfService, pdfBytes, fileName);
        
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al generar PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      } finally {
        isExporting.value = false;
      }
    }

    return Card(
      margin: const EdgeInsets.all(8),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Título
            Row(
              children: [
                Icon(Icons.filter_list, color: Colors.blue[700]),
                const SizedBox(width: 8),
                Text(
                  'Filtrar y Exportar',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue[700],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Campo de búsqueda
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: filterController,
                    decoration: InputDecoration(
                      hintText: 'Buscar por identificación, nombre o apellido...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    onChanged: _filterData,
                  ),
                ),
                const SizedBox(width: 8),
                if (filterController.text.isNotEmpty)
                  IconButton(
                    onPressed: () {
                      filterController.clear();
                      _filterData('');
                    },
                    icon: const Icon(Icons.clear),
                    tooltip: 'Limpiar filtro',
                  ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // Resultados del filtro
            if (showFilterResults.value) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: filteredData.value.isEmpty ? Colors.orange[50] : Colors.green[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: filteredData.value.isEmpty ? Colors.orange[200]! : Colors.green[200]!,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      filteredData.value.isEmpty ? Icons.warning : Icons.check_circle,
                      color: filteredData.value.isEmpty ? Colors.orange : Colors.green,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        filteredData.value.isEmpty
                            ? 'No se encontraron votantes con "${filterController.text}" en tu jerarquía'
                            : 'Encontrados ${filteredData.value.length} votantes que coinciden con "${filterController.text}"',
                        style: TextStyle(
                          color: filteredData.value.isEmpty ? Colors.orange[800] : Colors.green[800],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            
            // Estadísticas rápidas
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Datos disponibles:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue[800],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text('👥 Total: ${hierarchyData.length} votantes'),
                        if (showFilterResults.value)
                          Text('🔍 Filtrados: ${filteredData.value.length} votantes'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Botones de exportación
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: isExporting.value ? null : () => _exportPdf(),
                    icon: isExporting.value 
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.picture_as_pdf),
                    label: const Text('Exportar Todo'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: (isExporting.value || filterController.text.trim().isEmpty) 
                        ? null 
                        : () => _exportPdf(filtroIdentificacion: filterController.text.trim()),
                    icon: isExporting.value 
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.filter_alt),
                    label: const Text('Exportar Filtrado'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 8),
            
            // Información adicional
            Text(
              '💡 Tip: Solo puedes ver y exportar votantes que están en tu jerarquía. Si buscas una identificación que no aparece, significa que no está bajo tu liderazgo.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showPdfOptionsDialog(
    BuildContext context,
    PdfExportService pdfService,
    Uint8List pdfBytes,
    String fileName,
  ) async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.picture_as_pdf, color: Colors.red[600]),
            const SizedBox(width: 8),
            const Text('PDF Generado'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('¿Qué deseas hacer con el PDF generado?'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green[600]),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'PDF creado exitosamente con tu información jerárquica',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              Navigator.of(context).pop();
              try {
                await pdfService.sharePdf(pdfBytes, fileName);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('PDF compartido exitosamente'),
                    backgroundColor: Colors.green,
                  ),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Error al compartir: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            icon: const Icon(Icons.share),
            label: const Text('Compartir'),
          ),
          TextButton.icon(
            onPressed: () async {
              Navigator.of(context).pop();
              try {
                await pdfService.printPdf(pdfBytes);
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Error al imprimir: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            icon: const Icon(Icons.print),
            label: const Text('Imprimir'),
          ),
          TextButton.icon(
            onPressed: () async {
              Navigator.of(context).pop();
              try {
                final path = await pdfService.savePdfToDevice(pdfBytes, fileName);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('PDF guardado en: $path'),
                    backgroundColor: Colors.green,
                    duration: const Duration(seconds: 4),
                  ),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Error al guardar: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            icon: const Icon(Icons.save),
            label: const Text('Guardar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }
}

/// Widget compacto para mostrar solo los resultados del filtro
class FilterResultsWidget extends StatelessWidget {
  final List<Map<String, dynamic>> filteredData;
  final String searchTerm;
  final VoidCallback? onClearFilter;

  const FilterResultsWidget({
    Key? key,
    required this.filteredData,
    required this.searchTerm,
    this.onClearFilter,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (searchTerm.isEmpty) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  filteredData.isEmpty ? Icons.warning : Icons.filter_list,
                  color: filteredData.isEmpty ? Colors.orange : Colors.blue,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    filteredData.isEmpty
                        ? 'Sin resultados para "$searchTerm"'
                        : 'Filtrado: ${filteredData.length} resultados para "$searchTerm"',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: filteredData.isEmpty ? Colors.orange[800] : Colors.blue[800],
                    ),
                  ),
                ),
                if (onClearFilter != null)
                  IconButton(
                    onPressed: onClearFilter,
                    icon: const Icon(Icons.clear),
                    tooltip: 'Limpiar filtro',
                  ),
              ],
            ),
            if (filteredData.isEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'La identificación "$searchTerm" no se encuentra en tu jerarquía. Solo puedes ver votantes que están bajo tu liderazgo.',
                style: TextStyle(
                  color: Colors.orange[700],
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
