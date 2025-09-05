# Funcionalidades de Exportación PDF y Filtrado

## Descripción General

Se han implementado dos funcionalidades principales en la aplicación MiVoto:

1. **Exportación a PDF**: Generar documentos PDF con toda la información jerárquica del usuario
2. **Sistema de Filtrado**: Filtrar votantes por identificación, respetando la jerarquía del usuario

## Características Principales

### 🔒 Seguridad Jerárquica
- **Solo puedes ver datos de tu jerarquía**: El sistema respeta estrictamente los niveles jerárquicos
- **Filtrado seguro**: Si buscas una identificación que no está bajo tu liderazgo, no se mostrará
- **Exportación controlada**: Los PDFs solo incluyen información que tienes autorización para ver

### 📄 Exportación PDF

#### Tipos de Exportación:
1. **Exportar Todo**: Genera PDF con toda tu información jerárquica
2. **Exportar Filtrado**: Genera PDF solo con los resultados del filtro aplicado

#### Contenido del PDF:
- **Resumen Ejecutivo**: Estadísticas generales de tu jerarquía
- **Información del Usuario**: Tus datos y permisos
- **Estadísticas**: Distribución por roles, niveles y localidades
- **Jerarquía por Niveles**: Organización de votantes por nivel jerárquico
- **Distribución por Localidades**: Agrupación geográfica
- **Lista Detallada**: Tabla completa con información de votantes

#### Opciones de Salida:
- **Compartir**: Enviar PDF por WhatsApp, email, etc.
- **Imprimir**: Imprimir directamente desde la app
- **Guardar**: Almacenar en el dispositivo

### 🔍 Sistema de Filtrado

#### Criterios de Búsqueda:
- **Identificación**: Número de documento
- **Nombres**: Nombre completo o parcial
- **Apellidos**: Apellido completo o parcial

#### Funcionalidades:
- **Búsqueda en tiempo real**: Los resultados se actualizan mientras escribes
- **Respeto jerárquico**: Solo muestra resultados de tu jerarquía
- **Indicadores visuales**: Colores y iconos para identificar el estado del filtro
- **Limpieza rápida**: Botón para limpiar el filtro fácilmente

## Pantallas con Funcionalidad

### 1. Jerarquía por Localidad (`jerarquia_localidad.dart`)
- Widget de exportación y filtrado completo
- Integrado con la búsqueda existente por localidad
- Acceso a toda la jerarquía organizada geográficamente

### 2. Árbol Jerárquico (`arbol_screen.dart`)
- Widget de exportación disponible solo en el nodo raíz
- Permite exportar toda la estructura del árbol
- Filtrado para navegación rápida por identificación

### 3. Lista de Votantes (`votantes.dart`)
- Widget integrado en la parte superior de la lista
- Filtrado en tiempo real de la lista de votantes
- Exportación de la vista actual de votantes

## Uso Paso a Paso

### Para Exportar PDF:

1. **Accede a cualquiera de las pantallas**: Jerarquía Localidad, Árbol, o Votantes
2. **Localiza el widget "Filtrar y Exportar"**: Aparece como una tarjeta azul
3. **Opcional - Aplica un filtro**: Escribe en el campo de búsqueda para filtrar datos
4. **Selecciona tipo de exportación**:
   - **"Exportar Todo"**: Para exportar toda tu jerarquía
   - **"Exportar Filtrado"**: Para exportar solo los resultados filtrados
5. **Elige qué hacer con el PDF**:
   - **Compartir**: Enviar por apps instaladas
   - **Imprimir**: Imprimir directamente
   - **Guardar**: Almacenar en el dispositivo

### Para Filtrar Datos:

1. **Localiza el campo de búsqueda**: En el widget "Filtrar y Exportar"
2. **Escribe tu búsqueda**: Identificación, nombre o apellido
3. **Observa los resultados**: Se actualizan en tiempo real
4. **Interpreta los indicadores**:
   - 🟢 Verde: Resultados encontrados
   - 🟠 Naranja: Sin resultados en tu jerarquía
5. **Limpia el filtro**: Usa el botón "X" o borra el texto

## Mensajes del Sistema

### ✅ Éxito:
- "PDF generado exitosamente"
- "Encontrados X votantes que coinciden"
- "PDF compartido exitosamente"

### ⚠️ Advertencias:
- "No se encontraron votantes con [búsqueda] en tu jerarquía"
- "Solo puedes ver votantes que están bajo tu liderazgo"

### ❌ Errores:
- "Error al generar PDF: [detalle]"
- "Error al compartir: [detalle]"

## Consideraciones Técnicas

### Rendimiento:
- Los PDFs están limitados a 50 votantes en la tabla detallada para evitar documentos muy largos
- El filtrado es eficiente y funciona en tiempo real
- Los datos se cargan desde cache local cuando no hay internet

### Seguridad:
- Toda la lógica respeta los permisos jerárquicos del usuario
- No se pueden ver datos fuera de la jerarquía asignada
- Los filtros solo operan sobre datos autorizados

### Compatibilidad:
- Funciona tanto online como offline
- Compatible con el sistema de sincronización existente
- Integrado con el almacenamiento local de la app

## Dependencias Agregadas

```yaml
pdf: ^3.10.8          # Generación de documentos PDF
printing: ^5.12.0     # Impresión y compartir PDFs
path_provider: ^2.1.2 # Acceso al sistema de archivos
```

## Archivos Creados/Modificados

### Nuevos Archivos:
- `lib/services/pdf_export_service.dart`: Servicio principal de exportación PDF
- `lib/widgets/export_filter_widget.dart`: Widget de interfaz para filtrado y exportación

### Archivos Modificados:
- `pubspec.yaml`: Dependencias agregadas
- `lib/jerarquia_localidad.dart`: Integración del widget de exportación
- `lib/arbol_screen.dart`: Integración del widget de exportación
- `lib/votantes.dart`: Integración del widget de exportación

## Próximas Mejoras Sugeridas

1. **Filtros Avanzados**: Por localidad, rol, nivel jerárquico
2. **Plantillas PDF**: Diferentes formatos según el tipo de usuario
3. **Exportación Excel**: Alternativa a PDF para análisis de datos
4. **Programación de Reportes**: Generar reportes automáticos periódicos
5. **Gráficos y Estadísticas**: Visualizaciones en los PDFs

