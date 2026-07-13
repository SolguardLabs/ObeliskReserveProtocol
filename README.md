# Obelisk Reserve Protocol

![banner](./assets/banner.png)

Obelisk Reserve Protocol es un sistema de emisión y redención para una
stablecoin sobrecolateralizada. El protocolo mantiene posiciones de reserva,
distribuye liquidez entre buckets operativos, procesa redenciones diferidas y
permite recapitalización mediante un backstop pool.

## Componentes

- `ObeliskReservePool`: orquesta apertura de posiciones, mint, burn, retiradas,
  liquidación de tickets de redención y recapitalización.
- `ObeliskUSD`: stablecoin ERC-20 de 18 decimales con permisos de emisión y
  soporte EIP-2612.
- `ReserveRegistry`: registra activos, parámetros de riesgo, caps y pesos de
  buckets.
- `ReserveOracle`: publica precios normalizados a 18 decimales con heartbeat y
  límites.
- `DebtBook`: mantiene posiciones, colateral, deuda y agregados por activo.
- `LiquidityBuckets`: separa reservas en buckets immediate, deferred, strategic
  y backstop.
- `RedemptionQueue`: custodia el flujo diferido de redenciones y batch
  processing.
- `BackstopPool`: recibe liquidez de respaldo y puede aportar fondos al reserve
  pool.
- `FeeController`: calcula y acumula comisiones operativas por activo.
- `ReserveAccounting`: consolida actividad por epoch y cuenta.
- `ObeliskLens`: agrega vistas operativas para dashboards y monitores.
- `ParameterTimelock` y `KeeperRouter`: utilidades de gobierno y ejecución
  operativa.

## Modelo económico

Los usuarios abren posiciones depositando un activo admitido y emiten `oUSD`
hasta el LTV definido por el registro. El protocolo valida caps por activo,
ratios visibles de reserva y salud de la posición antes de emitir. Los burns
reducen deuda de una posición y liberan capacidad de retirada.

Las redenciones de `oUSD` se crean como tickets diferidos. Cuando el delay
finaliza, el keeper o cualquier integración autorizada puede procesar los
tickets contra los buckets disponibles. Las salidas aplican la comisión de
redención registrada para el activo. La liquidez del backstop puede
recapitalizar el reserve pool y se acredita en el bucket correspondiente.

## Seguridad y controles

- Separación de roles para administración, guardianes, keepers, riesgo,
  asignación de liquidez, recapitalización y settlement.
- Handover diferido para cambios de administración principal.
- Validación de precio vigente, caps, LTV, deuda mínima y estado del activo.
- Redenciones diferidas con delay, deadline y consumo ordenado de buckets.
- Accounting por epoch para actividad de reserva, comisiones y recapitalización.

Consulta [SECURITY.md](./SECURITY.md) para el modelo de amenazas, alcance de
revisión y proceso de reporte responsable.

## Requisitos

- Foundry 1.7 o superior.
- Solidity 0.8.28.
- Bash o PowerShell para los wrappers de validación.

## Comandos

```bash
forge build
forge test -vvv
bash scripts/ci.sh
```

En PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File ./scripts/tests.ps1
powershell -ExecutionPolicy Bypass -File ./scripts/ci.ps1
```

## Despliegue local

El script espera una clave de despliegue y un activo de reserva ya desplegado:

```bash
PRIVATE_KEY=... RESERVE_ASSET=0x... forge script script/DeployObelisk.s.sol:DeployObelisk \
  --rpc-url http://127.0.0.1:8545 --broadcast
```

`TREASURY` es opcional; si no se define, se usa el deployer.

## Estructura

```text
src/
  access/       roles y administración diferida
  core/         pool principal, registro, accounting, fees y libro de deuda
  governance/   timelock de parámetros
  interfaces/   interfaces ERC-20 y settlement
  lens/         vistas agregadas
  libraries/    aritmética, porcentajes, buckets y redenciones
  modules/      cola de redenciones
  oracle/       precios de reserva
  periphery/    router de keeper
  pools/        buckets y backstop
  token/        stablecoin del protocolo
  types/        estructuras compartidas
tests/          pruebas Forge de flujos públicos
script/         despliegue Foundry
scripts/        wrappers reproducibles de validación
```

## Cobertura funcional

La suite Forge cubre mint, burn, retirada de colateral, redenciones diferidas,
cancelación, expiración, batch processing, rebalanceo de buckets y
recapitalización desde backstop.
