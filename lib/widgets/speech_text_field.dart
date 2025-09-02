import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  bool _isListening = false;

  void _startVoiceInput() async {
    setState(() {
      _isListening = true;
    });

    // Vibración para feedback
    HapticFeedback.lightImpact();
    
    // Mostrar diálogo de voz
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.mic, color: Colors.red),
              SizedBox(width: 8),
              Text('Grabando...'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Habla ahora para ${widget.labelText?.toLowerCase() ?? 'este campo'}'),
              SizedBox(height: 16),
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.mic,
                  size: 30,
                  color: Colors.red,
                ),
              ),
              SizedBox(height: 16),
              Text(
                'Toca "Listo" cuando termines de hablar',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                setState(() {
                  _isListening = false;
                });
              },
              child: Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                // Simular reconocimiento de voz - en una implementación real
                // aquí se procesaría el audio capturado
                _simulateVoiceRecognition();
                Navigator.of(context).pop();
                setState(() {
                  _isListening = false;
                });
              },
              child: Text('Listo'),
            ),
          ],
        );
      },
    );
  }

  void _simulateVoiceRecognition() {
    // Esta función simula el reconocimiento de voz
    // En una implementación real, aquí se procesaría el audio
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.info, color: Colors.white),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Funcionalidad de voz disponible. Usa el teclado por voz de tu dispositivo para mejor experiencia.',
              ),
            ),
          ],
        ),
        backgroundColor: Colors.blue,
        duration: Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      decoration: InputDecoration(
        labelText: widget.labelText,
        hintText: widget.hintText,
        border: const OutlineInputBorder(),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: widget.enabled ? _startVoiceInput : null,
              icon: Icon(
                _isListening ? Icons.mic : Icons.mic_none,
                color: _isListening ? Colors.red : Colors.grey,
              ),
              tooltip: 'Usar entrada de voz',
            ),
            if (_isListening)
              Container(
                margin: const EdgeInsets.only(right: 8),
                child: const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
                  ),
                ),
              ),
          ],
        ),
      ),
      keyboardType: widget.keyboardType,
      enabled: widget.enabled,
      maxLines: widget.maxLines,
      validator: widget.validator,
      onChanged: widget.onChanged,
    );
  }
}
