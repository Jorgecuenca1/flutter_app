import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:avatar_glow/avatar_glow.dart';
import '../services/speech_cleanup_service.dart';

class SpeechTextField extends StatefulWidget {
  final TextEditingController controller;
  final String? labelText;
  final String? hintText;
  final TextInputType? keyboardType;
  final bool enabled;
  final int? maxLines;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  final bool isNumeric;

  const SpeechTextField({
    Key? key,
    required this.controller,
    this.labelText,
    this.hintText,
    this.keyboardType,
    this.enabled = true,
    this.maxLines = 1,
    this.validator,
    this.onChanged,
    this.isNumeric = false,
  }) : super(key: key);

  @override
  State<SpeechTextField> createState() => _SpeechTextFieldState();
}

class _SpeechTextFieldState extends State<SpeechTextField> {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _listening = false;
  String _speechPrev = '';

  Future<void> _toggleDictado() async {
    if (!_listening) {
      final available = await _speech.initialize(
        onStatus: (s) {
          print('Speech status: $s');
        },
        onError: (e) {
          print('Speech error: $e');
          setState(() => _listening = false);
        },
      );
      
      if (!available) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Speech-to-text no está disponible en este dispositivo'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      
      setState(() => _listening = true);
      _speechPrev = '';
      
      // Detectar conexión a internet al iniciar el dictado
      final hasInternet = await SpeechCleanupService.hasInternetConnection();
      
      await _speech.listen(
        onResult: (res) async {
          final recognized = res.recognizedWords.trim();
          if (recognized.isEmpty) return;

          // Procesar el texto usando el servicio
          final processedDelta = await SpeechCleanupService.processSpeechText(
            recognized,
            _speechPrev,
            isNumericField: widget.isNumeric,
            isOffline: !hasInternet,
          );

          if (processedDelta.isNotEmpty) {
            final current = widget.controller.text.trim();
            final newText = current.isEmpty ? processedDelta : '$current $processedDelta';
            
            widget.controller.text = newText;
            widget.controller.selection = TextSelection.fromPosition(
              TextPosition(offset: widget.controller.text.length),
            );
            
            if (widget.onChanged != null) {
              widget.onChanged!(widget.controller.text);
            }
          }

          _speechPrev = recognized;

          if (res.finalResult) {
            _speech.stop();
            setState(() => _listening = false);
            
            // Aplicar limpieza final adicional si no hay internet
            if (!hasInternet) {
              String finalText = SpeechCleanupService.cleanOfflineSpeechText(
                widget.controller.text, 
                isNumericField: widget.isNumeric
              );
              
              // Aplicar limpieza adicional más agresiva para casos extremos
              if (widget.isNumeric) {
                // Para números, asegurar que solo quedan dígitos y formato
                finalText = finalText.replaceAll(RegExp(r'[^\d\s+\-()]'), '');
                finalText = finalText.replaceAll(RegExp(r'(\d)\s+(\d)'), r'$1$2');
              } else {
                // Para texto, asegurar capitalización correcta
                if (finalText.isNotEmpty) {
                  finalText = finalText.split(' ').map((word) {
                    if (word.isEmpty) return word;
                    return word[0].toUpperCase() + word.substring(1).toLowerCase();
                  }).join(' ');
                }
              }
              
              if (finalText != widget.controller.text) {
                widget.controller.text = finalText;
                widget.controller.selection = TextSelection.fromPosition(
                  TextPosition(offset: widget.controller.text.length),
                );
                
                if (widget.onChanged != null) {
                  widget.onChanged!(widget.controller.text);
                }
              }
            }
          }
        },
        listenMode: stt.ListenMode.dictation,
        partialResults: true,
        localeId: null,
      );
    } else {
      await _speech.stop();
      setState(() => _listening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextFormField(
        controller: widget.controller,
        decoration: InputDecoration(
          labelText: widget.labelText,
          hintText: widget.hintText,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.blue, width: 2),
          ),
          filled: true,
          fillColor: Colors.grey.shade50,
          suffixIcon: Container(
            margin: const EdgeInsets.all(4),
            child: AvatarGlow(
              animate: _listening,
              glowColor: _listening ? Colors.red : Colors.blue,
              endRadius: 25.0,
              duration: const Duration(milliseconds: 2000),
              repeatPauseDuration: const Duration(milliseconds: 100),
              repeat: true,
              child: Material(
                elevation: 2,
                shape: const CircleBorder(),
                color: _listening ? Colors.red : Colors.grey.shade400,
                child: IconButton(
                  onPressed: widget.enabled ? _toggleDictado : null,
                  icon: Icon(
                    _listening ? Icons.mic : Icons.mic_none,
                    color: Colors.white,
                    size: 20,
                  ),
                  tooltip: 'Dictado por voz',
                ),
              ),
            ),
          ),
        ),
        keyboardType: widget.keyboardType,
        enabled: widget.enabled,
        maxLines: widget.maxLines,
        validator: widget.validator,
        onChanged: widget.onChanged,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _speech.stop();
    super.dispose();
  }
}