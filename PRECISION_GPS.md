# Mejoras de Precisión GPS Implementadas

## ✅ Cambios Aplicados

### 1. **AndroidSettings con `forceLocationManager`**
- Fuerza el uso del GPS físico en lugar de FusedLocationProvider
- En Android 12+ esto mejora significativamente la precisión
- `timeLimit` de 10 segundos espera por lectura GPS precisa

### 2. **Filtro de Media Móvil Ponderada**
- Implementado en `lib/core/utils/gps_filter.dart`
- Usa ventana de 3 lecturas
- Da más peso a lecturas con mejor `accuracy`
- Reduce el "salto" entre coordenadas

### 3. **Configuración `intervalDuration`**
- Actualización cada 1 segundo cuando estás en movimiento
- Más lecturas = mejor promedio = mejor precisión

### 4. **Requisito GPS Hardware**
- `AndroidManifest.xml` requiere GPS físico
- Evita dispositivos sin GPS que usan solo WiFi/celular

## 📊 Mejoras Esperadas

**Antes:**
```
Accuracy: 15-30m (FusedLocationProvider)
Saltos: ±5-10m entre lecturas
```

**Después:**
```
Accuracy: 3-8m (GPS directo + filtro)
Saltos: ±1-3m (suavizado por filtro)
```

## 🔧 Configuración Adicional Recomendada

### Para Android (`android/app/src/main/AndroidManifest.xml`):

Ya agregado:
```xml
<uses-feature android:name="android.hardware.location.gps" android:required="true" />
```

### Para iOS (`ios/Runner/Info.plist`):

Agregar estas claves para mejor precisión:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>Cingula necesita tu ubicación para reproducir audio geolocalizado</string>

<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>Cingula necesita tu ubicación para reproducir audio geolocalizado</string>

<!-- Solicitar precisión completa en iOS 14+ -->
<key>NSLocationTemporaryUsageDescriptionDictionary</key>
<dict>
    <key>FullAccuracyRequired</key>
    <string>Necesitamos precisión completa para activar triggers de audio en la ubicación correcta</string>
</dict>
```

## 🎯 Consejos de Uso en Campo

### 1. **Condiciones óptimas GPS**
- ✅ Cielo despejado (sin edificios altos, árboles densos)
- ✅ Esperar 30-60s después de abrir la app (GPS "warm-up")
- ✅ Mantener teléfono con pantalla hacia el cielo
- ❌ Evitar interiores, túneles, puentes

### 2. **Configuración del dispositivo**
```
Ajustes Android:
- Ubicación: Alta precisión / Usar GPS
- Modo ahorro batería: DESACTIVADO
- Precisión mejorada de Google: ACTIVADO
```

### 3. **Ajustes en la app**
En `LocationConfig`:
- `accuracyThresholdMeters`: 20m (ignorar lecturas peores)
- Reducir si necesitas más precisión: 10-15m
- Aumentar si ves muchas lecturas ignoradas: 25-30m

### 4. **Trigger radius óptimo**
- Mínimo recomendado: **8-10 metros**
- Por debajo de 8m: difícil activar consistentemente
- Considerar accuracy promedio de 5-8m en campo

## 🧪 Pruebas Recomendadas

### Test 1: Precisión estática
1. Parado en un lugar por 2 minutos
2. Ver logs de "Filtrada:" - debería estabilizarse en ±2m
3. Verificar accuracy < 10m consistentemente

### Test 2: Activación de trigger
1. Caminar hacia trigger desde fuera (20m)
2. Ver logs de `norm` decreciendo: 1.5 → 1.2 → 0.9 → **0.7 ✅**
3. Debe activar cuando `norm < 1.0`

### Test 3: Movimiento
1. Caminar ruta de 50m
2. Ver logs de "Filtrada:" - no debería saltar >5m
3. Triggers deberían activarse suavemente

## 📈 Monitoreo de Precisión

Los logs ahora muestran:
```
Lectura: lat=-34.123456, lon=-56.123456, accuracy=4.5m
Filtrada: lat=-34.123460, lon=-56.123461  // Solo si difiere
  Trigger id=1 name=Test: dist=8.2m radius=12m norm=0.68
Mejor trigger: id=1 norm=0.68 dist=8.2m ✅ ACTIVADO
```

Buscar en logs:
- `accuracy < 10m` → GPS funcionando bien
- `accuracy > 20m` → Lecturas ignoradas (buscar cielo más despejado)
- `Filtrada:` aparece → Filtro está suavizando saltos

## 🚀 Optimizaciones Futuras (Opcional)

### 1. **Filtro Kalman más sofisticado**
Ya está en `gps_filter.dart` pero no activado.
Para activar: cambiar `WeightedMovingAverageFilter` por `GPSFilter`

### 2. **Plugin GPS nativo**
Considerar `location` package en lugar de `geolocator` para más control.

### 3. **Corrección diferencial (DGPS)**
Requiere servidor NTRIP o estación base - complejo pero precisión <1m.

### 4. **Múltiples sensores**
Fusionar GPS + acelerómetro + brújula para dead reckoning.

## ⚠️ Limitaciones

1. **Precisión GPS civil**: 3-5m en condiciones ideales (límite del sistema)
2. **Multitrayectoria**: Señal rebota en edificios → error ±10m
3. **Ionosfera**: Clima solar puede degradar señal
4. **Hardware**: Chips GPS baratos = peor precisión

**Conclusión**: Con estos cambios deberías obtener **accuracy consistente de 3-8m** en campo abierto, suficiente para triggers de 10-15m de radio.
