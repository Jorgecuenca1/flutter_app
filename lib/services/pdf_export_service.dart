import 'dart:io';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'local_storage_service.dart';

class PdfExportService {
  final LocalStorageService _storage;

  PdfExportService(this._storage);

  /// Genera un PDF con toda la información jerárquica del usuario
  Future<Uint8List> generateHierarchyPdf({
    required String candidaturaId,
    required String candidaturaName,
    required Map<String, dynamic> userData,
    required List<Map<String, dynamic>> hierarchyData,
    String? filtroIdentificacion,
  }) async {
    final pdf = pw.Document();

    // Filtrar datos si se especifica una identificación
    List<Map<String, dynamic>> dataToExport = hierarchyData;
    if (filtroIdentificacion != null && filtroIdentificacion.trim().isNotEmpty) {
      dataToExport = hierarchyData.where((votante) {
        final identificacion = votante['identificacion']?.toString() ?? '';
        return identificacion.toLowerCase().contains(filtroIdentificacion.toLowerCase());
      }).toList();
    }

    // Información del usuario actual
    final userVotante = userData['votante'] ?? userData;
    final userName = '${userVotante['nombres'] ?? ''} ${userVotante['apellidos'] ?? ''}'.trim();
    final userRole = userVotante['pertenencia']?.toString() ?? 'Sin rol';
    final isCandidate = userVotante['es_candidato'] == true;
    final isJefe = userVotante['es_jefe'] == true;

    // Agrupar datos por localidad para el reporte
    final localidadData = _groupByLocalidad(dataToExport);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        header: (context) => _buildHeader(candidaturaName, userName, userRole),
        footer: (context) => _buildFooter(context),
        build: (context) => [
          // Resumen ejecutivo
          _buildExecutiveSummary(dataToExport, filtroIdentificacion),
          pw.SizedBox(height: 20),

          // Información del usuario
          _buildUserInfo(userData),
          pw.SizedBox(height: 20),

          // Estadísticas generales
          _buildStatistics(dataToExport, localidadData),
          pw.SizedBox(height: 20),

          // Jerarquía por niveles
          _buildHierarchyByLevels(dataToExport),
          pw.SizedBox(height: 20),

          // Información por localidades
          _buildLocalidadSection(localidadData),
          pw.SizedBox(height: 20),

          // Lista detallada de votantes
          _buildVotantesList(dataToExport),
        ],
      ),
    );

    return pdf.save();
  }

  /// Genera un PDF filtrado por identificación específica
  Future<Uint8List> generateFilteredPdf({
    required String candidaturaId,
    required String candidaturaName,
    required Map<String, dynamic> userData,
    required List<Map<String, dynamic>> hierarchyData,
    required String identificacion,
  }) async {
    // Buscar votantes que coincidan con la identificación
    final filteredData = hierarchyData.where((votante) {
      final votanteId = votante['identificacion']?.toString() ?? '';
      return votanteId.toLowerCase().contains(identificacion.toLowerCase());
    }).toList();

    if (filteredData.isEmpty) {
      // Crear PDF indicando que no se encontraron resultados
      return _generateNoResultsPdf(candidaturaName, identificacion);
    }

    return generateHierarchyPdf(
      candidaturaId: candidaturaId,
      candidaturaName: candidaturaName,
      userData: userData,
      hierarchyData: filteredData,
      filtroIdentificacion: identificacion,
    );
  }

  /// Guarda el PDF en el dispositivo y retorna la ruta
  Future<String> savePdfToDevice(Uint8List pdfBytes, String fileName) async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/$fileName');
    await file.writeAsBytes(pdfBytes);
    return file.path;
  }

  /// Comparte el PDF usando el sistema de compartir nativo
  Future<void> sharePdf(Uint8List pdfBytes, String fileName) async {
    await Printing.sharePdf(bytes: pdfBytes, filename: fileName);
  }

  /// Imprime el PDF directamente
  Future<void> printPdf(Uint8List pdfBytes) async {
    await Printing.layoutPdf(onLayout: (format) async => pdfBytes);
  }

  // Métodos privados para construir las secciones del PDF

  pw.Widget _buildHeader(String candidaturaName, String userName, String userRole) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 10),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: PdfColors.blue, width: 2)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'REPORTE JERÁRQUICO - MIVOTO',
                style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(candidaturaName, style: const pw.TextStyle(fontSize: 12)),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(userName, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.Text(userRole, style: const pw.TextStyle(fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _buildFooter(pw.Context context) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 10),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: PdfColors.grey, width: 1)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Generado el ${DateTime.now().toString().split(' ')[0]}',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey),
          ),
          pw.Text(
            'Página ${context.pageNumber} de ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildExecutiveSummary(List<Map<String, dynamic>> data, String? filtro) {
    final totalVotantes = data.length;
    final totalJefes = data.where((v) => v['es_jefe'] == true).length;
    final totalNiveles = data.map((v) => v['hierarchy_level'] ?? 0).reduce((a, b) => a > b ? a : b);

    return pw.Container(
      padding: const pw.EdgeInsets.all(15),
      decoration: pw.BoxDecoration(
        color: PdfColors.blue50,
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: PdfColors.blue200),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            filtro != null ? 'RESUMEN EJECUTIVO - FILTRADO' : 'RESUMEN EJECUTIVO',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800),
          ),
          if (filtro != null) ...[
            pw.SizedBox(height: 5),
            pw.Text('Filtro aplicado: "$filtro"', style: const pw.TextStyle(fontSize: 10, color: PdfColors.orange)),
          ],
          pw.SizedBox(height: 10),
          pw.Row(
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('👥 Total Votantes: $totalVotantes', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    pw.Text('👑 Total Jefes: $totalJefes'),
                    pw.Text('📊 Niveles Jerárquicos: $totalNiveles'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _buildUserInfo(Map<String, dynamic> userData) {
    final userVotante = userData['votante'] ?? userData;
    final userName = '${userVotante['nombres'] ?? ''} ${userVotante['apellidos'] ?? ''}'.trim();
    final userIdentification = userVotante['identificacion']?.toString() ?? 'Sin ID';
    final userRole = userVotante['pertenencia']?.toString() ?? 'Sin rol';
    final isCandidate = userVotante['es_candidato'] == true;
    final isJefe = userVotante['es_jefe'] == true;

    return pw.Container(
      padding: const pw.EdgeInsets.all(15),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'INFORMACIÓN DEL USUARIO',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800),
          ),
          pw.SizedBox(height: 8),
          pw.Text('Nombre: $userName'),
          pw.Text('Identificación: $userIdentification'),
          pw.Text('Rol: $userRole'),
          if (isCandidate) pw.Text('🎯 Es Candidato', style: pw.TextStyle(color: PdfColors.green)),
          if (isJefe) pw.Text('👑 Es Jefe', style: pw.TextStyle(color: PdfColors.orange)),
        ],
      ),
    );
  }

  pw.Widget _buildStatistics(List<Map<String, dynamic>> data, Map<String, List<Map<String, dynamic>>> localidadData) {
    final roleStats = <String, int>{};
    final levelStats = <int, int>{};
    
    for (final votante in data) {
      final role = votante['pertenencia']?.toString() ?? 'Sin rol';
      final level = votante['hierarchy_level'] ?? 0;
      
      roleStats[role] = (roleStats[role] ?? 0) + 1;
      levelStats[level] = (levelStats[level] ?? 0) + 1;
    }

    return pw.Container(
      padding: const pw.EdgeInsets.all(15),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'ESTADÍSTICAS GENERALES',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800),
          ),
          pw.SizedBox(height: 10),
          
          // Estadísticas por rol
          pw.Text('Por Roles:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          ...roleStats.entries.map((entry) => 
            pw.Text('  • ${entry.key}: ${entry.value} votantes')
          ).toList(),
          
          pw.SizedBox(height: 8),
          
          // Estadísticas por nivel jerárquico
          pw.Text('Por Niveles Jerárquicos:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          ...levelStats.entries.map((entry) => 
            pw.Text('  • Nivel ${entry.key}: ${entry.value} votantes')
          ).toList(),
          
          pw.SizedBox(height: 8),
          
          // Estadísticas por localidad
          pw.Text('Por Localidades:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.Text('  • Total localidades: ${localidadData.length}'),
        ],
      ),
    );
  }

  pw.Widget _buildHierarchyByLevels(List<Map<String, dynamic>> data) {
    final levelGroups = <int, List<Map<String, dynamic>>>{};
    
    for (final votante in data) {
      final level = votante['hierarchy_level'] ?? 0;
      levelGroups[level] = (levelGroups[level] ?? [])..add(votante);
    }

    final sortedLevels = levelGroups.keys.toList()..sort();

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'JERARQUÍA POR NIVELES',
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800),
        ),
        pw.SizedBox(height: 10),
        
        ...sortedLevels.map((level) {
          final votantes = levelGroups[level]!;
          return pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 10),
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: level == 1 ? PdfColors.green50 : PdfColors.grey50,
              border: pw.Border.all(color: level == 1 ? PdfColors.green200 : PdfColors.grey200),
              borderRadius: pw.BorderRadius.circular(5),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'NIVEL $level (${votantes.length} votantes)',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: level == 1 ? PdfColors.green800 : PdfColors.grey800),
                ),
                pw.SizedBox(height: 5),
                // Mostrar TODOS los votantes del nivel
                ...votantes.map((votante) {
                  final liderInfo = _getLiderInfo(votante, data);
                  return pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 2),
                    child: pw.Text(
                      '• ${votante['nombres'] ?? ''} ${votante['apellidos'] ?? ''} (${votante['identificacion'] ?? ''})${liderInfo.isNotEmpty ? ' - Lider: $liderInfo' : ''}',
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                  );
                }).toList(),
              ],
            ),
          );
        }).toList(),
      ],
    );
  }

  pw.Widget _buildLocalidadSection(Map<String, List<Map<String, dynamic>>> localidadData) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'DISTRIBUCIÓN POR LOCALIDADES',
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800),
        ),
        pw.SizedBox(height: 10),
        
        ...localidadData.entries.take(20).map((entry) {
          final localidad = entry.key;
          final votantes = entry.value;
          
          return pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 8),
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey300),
              borderRadius: pw.BorderRadius.circular(5),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  '$localidad (${votantes.length} votantes)',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
                ),
                ...votantes.take(5).map((votante) => pw.Text(
                  '  • ${votante['nombres'] ?? ''} ${votante['apellidos'] ?? ''} (${votante['identificacion'] ?? ''})',
                  style: const pw.TextStyle(fontSize: 9),
                )).toList(),
                if (votantes.length > 5)
                  pw.Text('  ... y ${votantes.length - 5} más', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey)),
              ],
            ),
          );
        }).toList(),
        
        if (localidadData.length > 20)
          pw.Text('... y ${localidadData.length - 20} localidades más', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey)),
      ],
    );
  }

  pw.Widget _buildVotantesList(List<Map<String, dynamic>> data) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'LISTA DETALLADA DE VOTANTES',
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800),
        ),
        pw.SizedBox(height: 10),
        
        // Tabla de votantes con estructura jerárquica
        _buildHierarchicalTable(data),
      ],
    );
  }

  pw.Widget _buildTableCell(String text, {bool isHeader = false}) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: isHeader ? 10 : 9,
          fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  Map<String, List<Map<String, dynamic>>> _groupByLocalidad(List<Map<String, dynamic>> data) {
    final groups = <String, List<Map<String, dynamic>>>{};
    
    for (final votante in data) {
      final localidad = _getVotanteLocalidad(votante);
      groups[localidad] = (groups[localidad] ?? [])..add(votante);
    }
    
    return groups;
  }

  String _getVotanteLocalidad(Map<String, dynamic> votante) {
    final ciudad = votante['ciudad_nombre']?.toString();
    final municipio = votante['municipio_nombre']?.toString();
    final comuna = votante['comuna_nombre']?.toString();
    final puesto = votante['puesto_votacion_nombre']?.toString();
    
    if (puesto != null && puesto.isNotEmpty) return puesto;
    if (comuna != null && comuna.isNotEmpty) return comuna;
    if (municipio != null && municipio.isNotEmpty) return municipio;
    if (ciudad != null && ciudad.isNotEmpty) return ciudad;
    return 'Sin localidad';
  }

  String _getLiderInfo(Map<String, dynamic> votante, List<Map<String, dynamic>> allData) {
    final lideres = votante['lideres'] as List<dynamic>?;
    if (lideres == null || lideres.isEmpty) return '';
    
    final liderId = lideres.first.toString();
    final lider = allData.firstWhere(
      (v) => v['id']?.toString() == liderId,
      orElse: () => <String, dynamic>{},
    );
    
    if (lider.isEmpty) return '';
    
    final liderNombre = '${lider['nombres'] ?? ''} ${lider['apellidos'] ?? ''}'.trim();
    final liderIdentificacion = lider['identificacion']?.toString() ?? '';
    return '$liderNombre ($liderIdentificacion)';
  }

  pw.Widget _buildHierarchicalTable(List<Map<String, dynamic>> data) {
    // Organizar datos por jerarquía
    final hierarchyMap = <String, List<Map<String, dynamic>>>{};
    final rootVotantes = <Map<String, dynamic>>[];
    
    // Identificar votantes raíz (nivel 1) y crear mapa de subordinados
    for (final votante in data) {
      final nivel = votante['hierarchy_level'] ?? 0;
      if (nivel == 1) {
        rootVotantes.add(votante);
        hierarchyMap[votante['id']?.toString() ?? ''] = [];
      }
    }
    
    // Agrupar subordinados bajo sus líderes
    for (final votante in data) {
      final nivel = votante['hierarchy_level'] ?? 0;
      if (nivel > 1) {
        final lideres = votante['lideres'] as List<dynamic>?;
        if (lideres != null && lideres.isNotEmpty) {
          final liderId = lideres.first.toString();
          if (hierarchyMap.containsKey(liderId)) {
            hierarchyMap[liderId]!.add(votante);
          }
        }
      }
    }
    
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Header de la tabla
        pw.Container(
          padding: const pw.EdgeInsets.all(8),
          decoration: const pw.BoxDecoration(color: PdfColors.blue100),
          child: pw.Row(
            children: [
              pw.Expanded(flex: 3, child: pw.Text('Nombre Completo', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10))),
              pw.Expanded(flex: 2, child: pw.Text('Identificación', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10))),
              pw.Expanded(flex: 1, child: pw.Text('Nivel', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10))),
              pw.Expanded(flex: 2, child: pw.Text('Rol', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10))),
              pw.Expanded(flex: 2, child: pw.Text('Localidad', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10))),
            ],
          ),
        ),
        
        // Datos organizados jerárquicamente
        ...rootVotantes.map((rootVotante) {
          return pw.Column(
            children: [
              // Votante principal (líder)
              _buildVotanteRow(rootVotante, isLeader: true),
              
              // Sus subordinados
              ...hierarchyMap[rootVotante['id']?.toString() ?? '']!.map((subordinado) {
                return _buildVotanteRow(subordinado, isSubordinate: true);
              }).toList(),
              
              // Separador entre grupos
              if (hierarchyMap[rootVotante['id']?.toString() ?? '']!.isNotEmpty)
                pw.Container(
                  height: 1,
                  margin: const pw.EdgeInsets.symmetric(vertical: 2),
                  color: PdfColors.grey300,
                ),
            ],
          );
        }).toList(),
        
        // Mostrar votantes sin líder identificado (si los hay)
        ...data.where((v) {
          final nivel = v['hierarchy_level'] ?? 0;
          final lideres = v['lideres'] as List<dynamic>?;
          return nivel > 1 && (lideres == null || lideres.isEmpty || !hierarchyMap.containsKey(lideres.first.toString()));
        }).map((votante) => _buildVotanteRow(votante, isOrphan: true)).toList(),
      ],
    );
  }

  pw.Widget _buildVotanteRow(Map<String, dynamic> votante, {bool isLeader = false, bool isSubordinate = false, bool isOrphan = false}) {
    final nombre = '${votante['nombres'] ?? ''} ${votante['apellidos'] ?? ''}'.trim();
    final identificacion = votante['identificacion']?.toString() ?? '';
    final nivel = votante['hierarchy_level']?.toString() ?? '0';
    final rol = votante['pertenencia']?.toString() ?? 'Sin rol';
    final localidad = _getVotanteLocalidad(votante);
    
    final backgroundColor = isLeader ? PdfColors.green50 : 
                          isSubordinate ? PdfColors.blue50 : 
                          isOrphan ? PdfColors.orange50 : 
                          PdfColors.white;
    
    final prefix = isSubordinate ? '  └─ ' : isOrphan ? '⚠ ' : '';
    
    return pw.Container(
      padding: const pw.EdgeInsets.all(6),
      decoration: pw.BoxDecoration(
        color: backgroundColor,
        border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
      ),
      child: pw.Row(
        children: [
          pw.Expanded(flex: 3, child: pw.Text('$prefix$nombre', style: pw.TextStyle(fontSize: 9, fontWeight: isLeader ? pw.FontWeight.bold : pw.FontWeight.normal))),
          pw.Expanded(flex: 2, child: pw.Text(identificacion, style: const pw.TextStyle(fontSize: 9))),
          pw.Expanded(flex: 1, child: pw.Text(nivel, style: const pw.TextStyle(fontSize: 9))),
          pw.Expanded(flex: 2, child: pw.Text(rol, style: const pw.TextStyle(fontSize: 9))),
          pw.Expanded(flex: 2, child: pw.Text(localidad, style: const pw.TextStyle(fontSize: 9))),
        ],
      ),
    );
  }

  Future<Uint8List> _generateNoResultsPdf(String candidaturaName, String identificacion) async {
    final pdf = pw.Document();
    
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        build: (context) => pw.Center(
          child: pw.Container(
            padding: const pw.EdgeInsets.all(30),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.orange, width: 2),
              borderRadius: pw.BorderRadius.circular(10),
            ),
            child: pw.Column(
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                pw.Icon(
                  pw.IconData(0xe002), // warning icon
                  size: 64,
                  color: PdfColors.orange,
                ),
                pw.SizedBox(height: 20),
                pw.Text(
                  'NO SE ENCONTRARON RESULTADOS',
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.orange,
                  ),
                ),
                pw.SizedBox(height: 15),
                pw.Text(
                  'La identificación "$identificacion" no se encuentra en tu jerarquía.',
                  style: const pw.TextStyle(fontSize: 14),
                  textAlign: pw.TextAlign.center,
                ),
                pw.SizedBox(height: 10),
                pw.Text(
                  'Solo puedes ver votantes que están bajo tu liderazgo en $candidaturaName.',
                  style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey),
                  textAlign: pw.TextAlign.center,
                ),
                pw.SizedBox(height: 20),
                pw.Text(
                  'Generado el ${DateTime.now().toString().split(' ')[0]}',
                  style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    
    return pdf.save();
  }
}

