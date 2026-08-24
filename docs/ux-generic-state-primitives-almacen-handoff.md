# M1 UX Generic State Primitives Almacén — handoff

## Autoridad y alcance

Este slice depende de `M1 Specification Manifest & Evidence Registry v1.2`, `M1 UX Component Inventory & State Matrix v0.1`, `M1 UX/UI & Design System Specification v0.1`, la dirección visual A+C / Almacén vigente y el contrato de accesibilidad, motion y haptics.

Ownership: UX/UI, Design System, interacción y experiencia mobile. Es Layer U solamente.

## Problema

El inventario canónico define `LoadingSkeleton`, `InlineError` y `EmptyState`, pero `main` no tenía primitives ejecutables equivalentes. Las surfaces existentes resolvían estados puntuales por separado, aumentando el riesgo de drift visual, semántico y responsive en futuros flujos.

## Alternativas

1. Mantener cada estado dentro de cada surface y aceptar duplicación.
2. Crear un único widget genérico extremadamente configurable para loading/error/empty.
3. Crear tres primitives pequeños con contratos diferenciados y materialidad Almacén compartida.

## Decisión

Se adopta la alternativa 3: `LoadingSkeleton`, `InlineError` y `EmptyState` como primitives independientes dentro de `design_system`.

## Rationale

Loading, error y vacío tienen semánticas distintas. Separarlos evita una API ambigua y permite que cada primitive mantenga su regla canónica: loading evita layout jump y no simula progreso autoritativo; error conserva el mensaje caller-owned y solo ofrece retry cuando el caller lo provee; empty state no introduce mascota, CTA ni contenido por defecto.

Los tres reutilizan tokens y primitives A+C / Almacén existentes, de modo que la identidad reside en materialidad y contenedor sin hacer que decoración cargue información crítica.

## Impacto

- reusable Layer U foundation para nuevas surfaces y refactors posteriores;
- target de retry/acciones >=44dp por Theme/controles existentes;
- reflow cubierto en 360dp con ~130% text scale;
- reduced motion no pierde estado porque `LoadingSkeleton` es estático;
- artwork y acciones de `EmptyState` son caller-owned;
- ningún cambio en gameplay, authority o contratos técnicos.

## Boundary DEC-065

No se incorporan nombres, valores, propiedades, transportes, cartas ni economía del fixture incompleto DEC-065. Tests y ejemplos usan texto explícitamente `PLACEHOLDER`.

## No-go / ownership

Este slice no modifica reglas, Engine, backend, routing, persistence, RNG, economía, deadlines, analytics, RoomCommand/GameCommand ni decisiones autoritativas. Tampoco reclama Character Sheet, fotos fuente, reconocimiento de personajes, VoiceOver/TalkBack manual, dispositivo físico ni human usability PASS.

## Evidencia executable objetivo

Los widget checks verifican:

- loading estático y semanticamente compuesto, sin spinner/motion que sugiera progreso autoritativo;
- inline error conserva copy caller-owned y retry opcional con target táctil;
- sin callback no se inventa retry;
- empty state no incluye character art por defecto;
- empty state reflowea a 360dp + ~130% text y mantiene acciones >=44dp.

Promover solo si el exact final head pasa CI canónico y PR Code Review GREEN.
