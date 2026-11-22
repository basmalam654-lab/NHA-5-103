Event-to-Chokepoint Mapping Rule

1. Purpose

This document defines the rules for linking disruption events to the chokepoints affected by those events.

The mapping results will be stored in the Gold Layer table:

"gold.bridge_event_chokepoint"

2. Source Data

The event mapping process uses the "affectedports" field from the disruption events source table.

This field may contain different types of identifiers, including:

- Chokepoint identifiers.
- Port identifiers.

Therefore, the values must be validated before creating relationships.

3. Mapping Rules

1. Direct Chokepoint Match: If an identifier in "affectedports" is confirmed to represent a valid chokepoint ID, it can be mapped directly to the corresponding "chokepoint_id".

2. Port Identifier: If an identifier represents a port ID, it must not be treated as a chokepoint ID. An approved and validated port-to-chokepoint mapping is required before linking it to a chokepoint.

3. Unverified Identifiers: Identifiers that cannot be confidently matched must be flagged for review. No relationship should be created based on assumptions.

4. Multiple Chokepoints: One event may affect more than one chokepoint. Each confirmed event-to-chokepoint relationship must be recorded separately.

5. No Valid Match: If no valid chokepoint can be identified, the event should remain without a chokepoint relationship until further validation is available.

4. Validation Requirements

Before loading records into "gold.bridge_event_chokepoint", verify that:

- Every "event_id" exists in "gold.dim_event".
- Every "chokepoint_id" exists in "gold.dim_chokepoint".
- No duplicate event-chokepoint pairs exist.
- All mappings are supported by validated source identifiers or an approved reference mapping.

5. Gold Layer Output

The final mapping will be stored in:

"gold.bridge_event_chokepoint"

Column| Description
event_id| Identifier of the disruption event
chokepoint_id| Identifier of the affected chokepoint

The table uses a composite primary key consisting of "event_id" and "chokepoint_id".

6. Important Note

The actual port-to-chokepoint mapping must be validated using the available source data and approved reference information.

Geographical proximity or country matching alone must not be used as proof that an event affected a specific chokepoint.

Unverified relationships must not be inserted into the Gold Layer.
