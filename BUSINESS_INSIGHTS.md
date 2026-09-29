# Business insights, decisions, and risks

The command center is designed to make a decision traceable: start with a
signal, diagnose its drivers, assess forecast uncertainty, then choose a
proportionate operating response. Numbers are intentionally refreshed from
Snowflake rather than hard-coded in documentation.

## Decision signals

| Signal | Where to inspect it | What it means | Suggested response |
| --- | --- | --- | --- |
| Demand accelerating | Executive Pulse, Demand Intelligence | Units exceed the selected 30-day baseline by more than 10%. | Prioritize availability for the affected category, item, and store; check that the rise is sustained before making a broad commitment. |
| Demand softening | Demand Intelligence, Action & Risk Center | Units are more than 10% below the selected 30-day baseline. | Diagnose price, event timing, product mix, and state/store exposure before discounting. |
| High forecast uncertainty | Forecast Control Tower | The 95% forecast interval is wider than 75% of the forecast level. | Use a conservative reorder quantity, retain flexible capacity, and increase review cadence. |
| Price-demand warning | Price & Calendar Drivers | A material price increase coincides with a demand decline, or a discount with a demand rise. | Treat this as an association, not proof of elasticity; run a targeted test and protect margin. |
| Revenue concentration | Executive Pulse, Demand Intelligence | A small set of categories or departments carries a high share of selected revenue. | Protect availability for key drivers while creating contingency plans for supply disruption. |
| Calendar sensitivity | Price & Calendar Drivers | Revenue differs by event type, day type, or SNAP timing. | Align inventory and local staffing with recurring patterns; validate across comparable periods. |

## Risks and guardrails

- Future forecast rows do not have actual outcomes yet. Do not label an interval
  width or a future forecast as accuracy. Use backtest/evaluation marts for
  measurable model performance.
- Price, event, and SNAP visuals describe observed patterns. The M5 data is not
  a causal experiment, so changes should be tested before broad rollout.
- Forecast revenue is an estimate based on forecast units and recent average
  selling price; it is not a price forecast or booked revenue.
- The production forecast is item-date grain while historical sales are
  item-store-date grain. Review store exposure separately when converting a
  category signal into a store-level replenishment decision.
- Missing source, fact, or forecast coverage invalidates a dashboard result.
  Run the quality controls before distributing it.

## Operating cadence

1. Refresh Snowflake and dbt outputs; resolve test failures first.
2. Review the Executive Pulse for the material change.
3. Use Demand Intelligence and Price & Calendar Drivers to explain it.
4. Use the Forecast Control Tower to size uncertainty and select an action.
5. Recheck the signal after the next refresh to validate the outcome.

The dashboard exposes this workflow directly through its measures:
`Demand Signal`, `Pricing Signal`, `Forecast Risk Status`, and
`Recommended Action`.
