# Modelo de seguridad y riesgos

## Fronteras de confianza

Las llamadas de usuario entran por el pool o la cola. Un administrador configura contratos y políticas; un reportero actualiza el oráculo; un guardian activa pausas; un keeper procesa lotes; un asignador mueve saldos entre buckets. Son poderes distintos y deben custodiarse por separado. Los ERC-20 y feeds conectados son dependencias externas al código del pool.

| Riesgo operativo | Evidencia disponible | Respuesta esperada |
| --- | --- | --- |
| Precio vencido o fuera de banda | Estado del feed y revert del registro | Suspender emisión/salida afectada y validar fuente |
| Concentración de un activo | `assetSnapshots` y escenario de estrés | Revisar límites de activo y liquidez de salida |
| Insuficiencia de bucket | `bucketState`, cotización de waterfall | Planificar rebalanceo o backstop autorizado |
| Posición cerca de LTV | `positionView` y `maxMintable` | Evitar ampliación; revisar precio y colateral |
| Compromiso de clave de rol | Eventos de permisos y cambios de política | Pausa, rotación y revisión de transacciones |

Los monitores pueden combinar señales, pero no deben presentar un resultado de estrés como prueba de solvencia. `ReserveStressEngine` acepta escenarios externos; no obtiene precios ni valida que representen el mercado. La cobertura de tests locales tampoco sustituye un análisis de propiedades bajo tokens con transferencias no estándar, feeds adversos o configuraciones de gobierno concretas.

## Evidencia de cambios

Cada cambio de parámetros debe conservar la propuesta, el estado previo, la transacción, el estado posterior y la justificación del operador. Para una revisión de seguridad, documenta rutas de autorización y límites por activo en el commit exacto que se esté evaluando.
