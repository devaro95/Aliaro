# TODO

## Bugs

- [ ] **Sync del menú semanal entre miembros de la familia** (detectado 26/10/2026, familia de alvaromcarmena95@gmail.com)
  - Síntoma: Alicia cambió la comida del martes y a Alvaro no se le actualizó.
  - Causa 1: el cliente guarda por `id` y, si no tiene la fila del hueco en caché, inserta una nueva con otro UUID → dos filas para el mismo (familia, día, comida).
  - Causa 2: `meal_plan_entries` no tiene `UNIQUE (family_id, weekday, meal_type)`.
  - Causa 3: Realtime con filtro por `family_id` no entrega los DELETE (solo llevan el `id`), así que los borrados no llegan a otros dispositivos; además la caché local no elimina las filas que ya no existen en el servidor.
  - Arreglo app: guardar con `upsert(onConflict = "family_id,weekday,meal_type")`; en la carga completa, reemplazar la caché local por lo que devuelve el servidor; no depender de eventos DELETE de Realtime.
  - Arreglo BD (HECHO 26/10/2026, migración `meal_plan_entries_unique_slot`): trigger `BEFORE INSERT` que borra la fila previa del mismo hueco + constraint `UNIQUE (family_id, weekday, meal_type)`.
  - Hecho: borrado el duplicado («Lentejas», martes comida) en producción.
