# UX Ajustes + Accesibilidad Almacén — handoff

## Alcance

Layer U / presentación solamente. Fuente canónica: `M1 Specification Manifest & Evidence Registry v1.2`, `M1 UX/UI & Design System Specification v0.1`, `M1 UX Accessibility, Motion & Haptics Acceptance Specification v0.1` y la dirección A+C / Almacén vigente.

La IA canónica incluye `Ajustes / Accesibilidad`, pero el executable no tenía una surface ni un contrato de presentación para esa entrada. Este cambio materializa ese hueco sin definir dónde se persisten preferencias ni cómo el sistema operativo o la plataforma aplican motion, haptics, audio o tamaño de texto.

## Problema

Una pantalla de ajustes con toggles hardcodeados sería visualmente rápida de construir, pero convertiría decisiones todavía no especificadas en policy de producto y podría hacer que la UI se apropiara de estado que pertenece al sistema operativo, a la integración mobile o a una futura capa de persistencia.

## Alternativas

1. No materializar `Ajustes / Accesibilidad` hasta cerrar todas las preferencias finales.
2. Hardcodear toggles comunes como motion, haptics, sonido y contraste y persistirlos localmente.
3. Crear una surface data-driven: secciones e items caller-owned, con filas `toggle`, `action` y `status`; la UI muestra el estado recibido y emite intención por ID, sin persistir ni aplicar policy.

## Decisión

Se adopta la alternativa 3. `AccessibilitySettingsSurface` recibe secciones e items caller-owned. Un toggle emite `(settingId, nextValue)`; una acción emite `settingId`; una fila de estado es estrictamente read-only. El caller conserva la fuente de verdad y debe reinyectar el estado si cambia.

## Rationale

- Materializa la IA canónica sin inventar preferencias.
- Mantiene separadas preferencia de sistema, presentación y gameplay authority.
- Permite que reduced motion y haptics sigan siendo preferencias independientes como exige el contrato UX.
- Preserva rebrandabilidad y reutiliza materialidad Almacén mediante `PaperPanel`, `StampBadge` y `TapeMark`.
- Evita `SharedPreferences`, routing y APIs de plataforma dentro del frente UX.

## Impacto

- Nuevo entry point presentacional reutilizable para Ajustes/Accesibilidad.
- Targets interactivos >=44dp.
- Filas disabled conservan una razón visible y semántica.
- Filas status no se exponen como acción.
- Reflow cubierto a 360dp con ~130% de texto.
- La surface es estática y no depende de motion para comunicar estado.

## Boundary de autoridad

No implementa persistencia de preferencias, routing, deep links, APIs del sistema operativo, haptics reales, audio real, lectura/escritura de accessibility settings del dispositivo, analytics, Engine, backend, reglas, economía, RNG, authority, timers ni deadlines.

Los labels y valores concretos de preferencias son caller-owned. Los fixtures de test usan `PLACEHOLDER` donde corresponde. No se reconstruye ni consume el payload pendiente de DEC-065.

## Evidence boundary

Los widget tests de esta slice prueban presentación, callbacks, disabled/read-only semantics, target size y responsive/reduced-motion-safe geometry. No constituyen PASS manual de VoiceOver/TalkBack, hardware haptics, dispositivos físicos, settings reales del OS ni usabilidad humana.
