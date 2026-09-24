# UAT vs SAPSF — Metadata Diff Summary

- Generated: `2026-09-24T15:44:29.758041+00:00`
- Orgs: `ICB-UAT` vs `ICB-SAPSF`
- Excel: `snapshots/reports/UAT_vs_SAPSF_metadata_diff.xlsx`
- CSV: `snapshots/reports/UAT_vs_SAPSF_metadata_diff.csv`

## Totales por DiffStatus

| DiffStatus | Count |
|------------|------:|
| `OnlyInSAPSF` | 6896 |
| `InBoth_DifferentUser` | 3635 |
| `InBoth_DifferentDate` | 2483 |
| `InBoth_SameDate` | 1522 |
| `InBoth_DifferentDateAndUser` | 846 |
| `OnlyInUAT` | 616 |

**Total componentes inventariados:** 15998
**Con diferencia (≠ InBoth_SameDate):** 14476

## Top 20 MetadataType con más diferencias

| MetadataType | Diff count |
|--------------|----------:|
| `CustomMetadata` | 6042 |
| `CustomObjectTranslation` | 2838 |
| `CustomField` | 1906 |
| `ApexClass` | 656 |
| `CustomObject` | 438 |
| `SharingRules` | 267 |
| `Layout` | 197 |
| `TopicsForObjects` | 190 |
| `Settings` | 184 |
| `Flow` | 161 |
| `FlowDefinition` | 161 |
| `WorkflowFlowAutomation` | 161 |
| `LightningComponentBundle` | 104 |
| `ListView` | 95 |
| `DigitalExperience` | 78 |
| `ApexPage` | 63 |
| `PermissionSet` | 61 |
| `FlexiPage` | 59 |
| `GlobalValueSetTranslation` | 54 |
| `ValidationRule` | 52 |

## Hojas del Excel

- **Summary** — conteos por status y por tipo
- **AllComponents** — inventario completo
- **AllDifferences** — todo lo que no es InBoth_SameDate
- **OnlyInUAT** / **OnlyInSAPSF**
- **ModifiedDifferent** — existe en ambos con distinta fecha y/o usuario

