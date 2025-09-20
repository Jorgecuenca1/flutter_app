import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

class LocationService {
  static Future<bool> checkAndRequestPermissions() async {
    // Verificar si el servicio de ubicación está habilitado
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // El servicio de ubicación no está habilitado
      return false;
    }

    // Verificar permisos de ubicación
    LocationPermission permission = await Geolocator.checkPermission();
    
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        // Permisos denegados
        return false;
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      // Permisos denegados permanentemente
      return false;
    }

    // Permisos concedidos
    return true;
  }

  static Future<Map<String, double>?> getCurrentLocation() async {
    try {
      bool hasPermission = await checkAndRequestPermissions();
      if (!hasPermission) {
        return null;
      }

      // Obtener la posición actual
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      return {
        'latitud': position.latitude,
        'longitud': position.longitude,
        'precision': position.accuracy,
      };
    } catch (e) {
      print('Error obteniendo ubicación: $e');
      return null;
    }
  }

  static Future<void> showLocationPermissionDialog(BuildContext context) async {
    return showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Permisos de Ubicación'),
          content: const Text(
            'Esta aplicación necesita acceso a tu ubicación para guardar la ubicación de los votantes. '
            'Esto ayuda a organizar mejor las campañas y eventos.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await openAppSettings();
              },
              child: const Text('Abrir Configuración'),
            ),
          ],
        );
      },
    );
  }

  static double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    return Geolocator.distanceBetween(lat1, lon1, lat2, lon2);
  }
}