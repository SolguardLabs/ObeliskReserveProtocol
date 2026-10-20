# Integración local

## Preparación verificable

La suite Forge despliega `rUSDC`, `oUSD`, oráculo, registro, libro de deuda, buckets, backstop, pool y cola en una EVM efímera. `tests/helpers/ObeliskTestBase.sol` muestra el orden de construcción y la asignación de roles necesarios. Para integrar otro activo, verifica la escala de decimales, el feed, `depositCap`, `issuanceCap`, LTV, ratio de liquidación, comisión, pesos de bucket y permisos antes de habilitarlo.

```bash
bash scripts/bootstrap.sh
forge build
forge test --match-contract MintBurnTest -vv
forge test --match-contract RedemptionQueueTest -vv
```

Las pruebas usan direcciones y tokens de test; no requieren RPC externo. Si se utiliza `script/DeployObelisk.s.sol`, ejecútalo únicamente contra un nodo local controlado y revisa las variables de entorno que exige el script. No almacenes claves en archivos versionados.

## Apertura y emisión

El cliente aprueba el token de colateral al pool y llama `openPosition(asset, collateralAmount, mintAmount, receiver)`. El pool consulta el registro, recibe el activo, distribuye su balance en buckets y, si `mintAmount > 0`, comprueba salud, caps, mínimo y cobertura antes de acuñar. `positionView(id)` y `maxMintable(id)` permiten mostrar límites indicativos. `mintStable` amplía deuda de una posición existente, con las mismas restricciones aplicables.

## Salida diferida

Para solicitar una salida, el titular aprueba `oUSD` a la cola y llama `requestRedemption(asset, stableAmount, minOut, receiver, deadline)`. El ticket puede ejecutarse a partir de `executableAt` y antes de `deadline`; `executeRedemption(id)` liquida contra el pool. `cancelRedemption` y `expireRedemption` tienen condiciones distintas; el cliente debe mostrar estado, retraso, cantidad mínima y vencimiento antes de firmar.

| Consulta | Uso del cliente |
| --- | --- |
| `ObeliskLens.protocolSnapshot()` | Estado agregado de reserva y emisión |
| `ObeliskLens.assetSnapshot(asset)` | Parámetros y exposición de un activo |
| `ObeliskLens.bucketState(asset)` | Liquidez por bucket |
| `RedemptionQueue.ticket(id)` | Estado y plazo de una solicitud |

Las vistas son instantáneas. Un precio o balance puede cambiar entre consulta y transacción; no reduzcas automáticamente `minOut` tras un revert.
