// lib/services/speech_cleanup_service.dart
import 'package:connectivity_plus/connectivity_plus.dart';

class SpeechCleanupService {
  /// Limpia texto de reconocimiento de voz sin internet que deja espacios entre letras
  static String cleanOfflineSpeechText(String input, {bool isNumericField = false}) {
    if (input.isEmpty) return input;
    
    String cleaned = input.toLowerCase().trim();
    
    // 1. Para campos numéricos, aplicar limpieza especializada
    if (isNumericField) {
      cleaned = _cleanNumericSpeechText(cleaned);
    } else {
      // 2. Para texto normal, aplicar múltiples estrategias de limpieza
      cleaned = _cleanTextSpeech(cleaned);
    }
    
    return cleaned;
  }

  /// Limpieza avanzada para texto normal
  static String _cleanTextSpeech(String input) {
    String cleaned = input;
    
    // 1. Remover caracteres especiales problemáticos del speech-to-text offline
    cleaned = cleaned.replaceAll(RegExp(r'[^\w\sáéíóúñü]'), '');
    
    // 2. Corregir espacios entre letras individuales: "j u a n" -> "juan"
    // Patrón más agresivo para capturar letras separadas
    cleaned = cleaned.replaceAll(RegExp(r'\b([a-záéíóúñü])\s+(?=[a-záéíóúñü]\b)'), r'$1');
    
    // 3. Corregir patrones específicos del speech offline
    cleaned = cleaned.replaceAll(RegExp(r'(\w)\s+(\w)\s+(\w)'), r'$1$2$3'); // 3 letras separadas
    cleaned = cleaned.replaceAll(RegExp(r'(\w)\s+(\w)(?=\s|$)'), r'$1$2'); // 2 letras separadas
    
    // 4. Limpiar múltiples espacios
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
    
    // 5. Capitalizar correctamente
    if (cleaned.isNotEmpty) {
      cleaned = cleaned.split(' ').map((word) {
        if (word.isEmpty) return word;
        return word[0].toUpperCase() + word.substring(1).toLowerCase();
      }).join(' ');
    }
    
    return cleaned;
  }

  /// Limpieza especializada para campos numéricos
  static String _cleanNumericSpeechText(String input) {
    String cleaned = input.toLowerCase().trim();
    
    // 1. Mapeo extendido de números en palabras a dígitos
    final numberWords = {
      // Números básicos
      'cero': '0', 'uno': '1', 'dos': '2', 'tres': '3', 'cuatro': '4',
      'cinco': '5', 'seis': '6', 'siete': '7', 'ocho': '8', 'nueve': '9',
      
      // Números del 10-30
      'diez': '10', 'once': '11', 'doce': '12', 'trece': '13', 'catorce': '14',
      'quince': '15', 'dieciséis': '16', 'diecisiete': '17', 'dieciocho': '18',
      'diecinueve': '19', 'veinte': '20',
      
      // Variaciones comunes del speech-to-text
      'un': '1', 'una': '1', 'primera': '1', 'segundo': '2', 'tercero': '3',
      'cuarta': '4', 'quinta': '5', 'sexta': '6', 'séptima': '7', 'octava': '8',
      
      // Números compuestos frecuentes
      'veintiuno': '21', 'veintidós': '22', 'veintitrés': '23', 'veinticuatro': '24',
      'veinticinco': '25', 'veintiséis': '26', 'veintisiete': '27', 'veintiocho': '28',
      'veintinueve': '29', 'treinta': '30',
      
      // Variaciones con errores comunes del speech
      'sero': '0', 'ero': '0', 'bero': '0', // cero mal reconocido
      'no': '1', 'uno': '1', 'huno': '1', // uno mal reconocido
      'os': '2', 'dose': '2', 'doz': '2', // dos mal reconocido
      'res': '3', 'tree': '3', 'trez': '3', // tres mal reconocido
      'uatro': '4', 'cuatros': '4', // cuatro mal reconocido
      'inco': '5', 'sinco': '5', // cinco mal reconocido
      'eis': '6', 'seys': '6', // seis mal reconocido
      'iete': '7', 'sietes': '7', // siete mal reconocido
      'cho': '8', 'ochos': '8', // ocho mal reconocido
      'ueve': '9', 'nueves': '9', // nueve mal reconocido
    };
    
    // 2. Reemplazar números en palabras (orden importante: más largos primero)
    final sortedWords = numberWords.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
    for (final word in sortedWords) {
      cleaned = cleaned.replaceAll(RegExp(r'\b' + RegExp.escape(word) + r'\b'), numberWords[word]!);
    }
    
    // 3. Limpiar espacios entre dígitos: "3 1 2 4 5 6 7 8 9 0" -> "3124567890"
    // Múltiples pasadas para asegurar limpieza completa
    for (int i = 0; i < 3; i++) {
      cleaned = cleaned.replaceAll(RegExp(r'(\d)\s+(\d)'), r'$1$2');
    }
    
    // 4. Limpiar caracteres no numéricos excepto espacios para formateo final
    cleaned = cleaned.replaceAll(RegExp(r'[^\d\s]'), '');
    
    // 5. Limpiar espacios múltiples
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
    
    // 6. Formatear números de teléfono si parece ser uno
    final digitsOnly = cleaned.replaceAll(RegExp(r'[^\d]'), '');
    if (digitsOnly.length >= 10) {
      if (digitsOnly.length == 10) {
        // Formato colombiano: XXX XXX XXXX
        cleaned = '${digitsOnly.substring(0, 3)} ${digitsOnly.substring(3, 6)} ${digitsOnly.substring(6)}';
      } else if (digitsOnly.length == 11 && digitsOnly.startsWith('57')) {
        // Formato con código país: +57 XXX XXX XXXX
        cleaned = '+57 ${digitsOnly.substring(2, 5)} ${digitsOnly.substring(5, 8)} ${digitsOnly.substring(8)}';
      } else if (digitsOnly.length == 12 && digitsOnly.startsWith('57')) {
        // Formato con código país extendido
        cleaned = '+57 ${digitsOnly.substring(2, 5)} ${digitsOnly.substring(5, 8)} ${digitsOnly.substring(8)}';
      } else {
        // Para otros casos, solo devolver los dígitos
        cleaned = digitsOnly;
      }
    } else {
      // Para números cortos, devolver solo los dígitos
      cleaned = digitsOnly;
    }
    
    return cleaned;
  }

  /// Detecta si hay conexión a internet
  static Future<bool> hasInternetConnection() async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      return connectivityResult.contains(ConnectivityResult.none) == false;
    } catch (e) {
      return false;
    }
  }

  /// Limpia texto duplicado manteniendo solo palabras únicas
  static String dedupeWords(String input, {bool nonAdjacent = false}) {
    final parts = input.split(RegExp(r'\s+'));
    final List<String> out = [];
    final Set<String> seen = <String>{};
    for (final raw in parts) {
      final w = raw.trim();
      if (w.isEmpty) continue;
      final lower = w.toLowerCase();
      if (nonAdjacent) {
        if (seen.contains(lower)) continue;
        seen.add(lower);
        out.add(w);
      } else {
        if (out.isEmpty || out.last.toLowerCase() != lower) {
          out.add(w);
        }
      }
    }
    return out.join(' ');
  }

  /// Procesa texto de speech-to-text aplicando todas las limpiezas necesarias
  static Future<String> processSpeechText(
    String recognizedText, 
    String previousText, {
    bool isNumericField = false,
    bool isOffline = false,
  }) async {
    if (recognizedText.isEmpty) return recognizedText;

    // Calcular solo el delta para evitar repeticiones
    String delta;
    if (recognizedText.toLowerCase().startsWith(previousText.toLowerCase())) {
      delta = recognizedText.substring(previousText.length);
    } else {
      if (recognizedText.toLowerCase() == previousText.toLowerCase()) {
        delta = '';
      } else {
        delta = recognizedText;
      }
    }

    if (delta.isEmpty) return '';

    // Aplicar limpieza básica
    String processed = dedupeWords(delta, nonAdjacent: true);
    
    // Si no hay internet, aplicar limpieza adicional más agresiva
    if (isOffline) {
      processed = cleanOfflineSpeechText(processed, isNumericField: isNumericField);
      
      // Aplicar limpieza adicional para casos extremos offline
      if (isNumericField) {
        // Para números, aplicar limpieza extra
        processed = _extraNumericCleanup(processed);
      } else {
        // Para texto, aplicar limpieza extra
        processed = _extraTextCleanup(processed);
      }
    }

    return processed;
  }

  /// Limpieza extra para números en casos extremos offline
  static String _extraNumericCleanup(String input) {
    String cleaned = input;
    
    // Remover cualquier letra que haya quedado mezclada
    cleaned = cleaned.replaceAll(RegExp(r'[a-zA-ZáéíóúñüÁÉÍÓÚÑÜ]'), '');
    
    // Asegurar que no hay espacios entre dígitos
    cleaned = cleaned.replaceAll(RegExp(r'(\d)\s+(\d)'), r'$1$2');
    
    // Limpiar caracteres especiales
    cleaned = cleaned.replaceAll(RegExp(r'[^\d\s+\-()]'), '');
    
    return cleaned.trim();
  }

  /// Limpieza extra para texto en casos extremos offline
  static String _extraTextCleanup(String input) {
    String cleaned = input;
    
    // Remover números sueltos que no deberían estar en texto
    cleaned = cleaned.replaceAll(RegExp(r'\b\d+\b'), '');
    
    // Limpiar caracteres especiales problemáticos
    cleaned = cleaned.replaceAll(RegExp(r'[^\w\sáéíóúñüÁÉÍÓÚÑÜ]'), '');
    
    // Asegurar espacios correctos entre palabras
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ');
    
    return cleaned.trim();
  }
}

