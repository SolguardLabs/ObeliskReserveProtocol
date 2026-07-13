# Política de seguridad

Obelisk Reserve Protocol protege emisión de `oUSD`, custodia de reservas,
redenciones diferidas y recapitalización mediante buckets de liquidez. Esta
política define el alcance de revisión, las invariantes esperadas y el proceso
para comunicar comportamientos de riesgo.

## Alcance

Incluye todos los contratos bajo `src/`, pruebas Forge, scripts de despliegue y
configuración de CI. Quedan fuera integraciones externas no incluidas en este
repositorio, oráculos operados fuera del código publicado, wallets, frontends y
parámetros específicos de una red concreta.

## Modelo de seguridad

El protocolo usa roles separados para administración, guardianes, keepers,
asignadores de liquidez, riesgo, recapitalización y settlement de redenciones.
Las funciones de alto impacto quedan restringidas a módulos concretos y los
cambios de administrador principal usan un handover diferido.

## Invariantes esperadas

- Las posiciones no pueden emitir por encima del LTV configurado para su activo.
- Los activos admitidos deben tener precio vigente y estar habilitados en el
  registro.
- Los depósitos respetan caps por activo y se distribuyen entre buckets
  configurados.
- Las redenciones solo se ejecutan tras el delay y antes de su deadline.
- Las salidas de reserva consumen liquidez siguiendo el orden de buckets.
- La recapitalización solo puede extraer fondos de un backstop autorizado.

## Validación local

```bash
forge fmt --check
forge build
forge test -vvv
```

Los tests cubren operaciones de usuario, permisos, lifecycle de tickets, batch
processing, rebalanceo y backstop. Las dependencias de CI se mantienen mediante
GitHub Actions y Dependabot.

## Reporte responsable

Un reporte debe incluir:

- descripción del comportamiento observado;
- impacto económico y activos afectados;
- precondiciones necesarias;
- secuencia mínima de verificación;
- propuesta de mitigación;
- tests que deberían fallar antes del cambio y pasar después.

No incluyas claves privadas, credenciales, seeds ni datos de terceros.
