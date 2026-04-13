# ZTS Cluster Mapping

## Cluster Table

| Environment | Cluster URI | Database |
|---|---|---|
| Dev | `https://ztsdev.westus3.kusto.windows.net` | Log |
| DVX1 | `https://ztsdvx1.uksouth.kusto.windows.net` | Log |
| DVX2 | `https://ztsdvx2.uksouth.kusto.windows.net` | Log |
| DVX3 | `https://ztsdvx3.uksouth.kusto.windows.net` | Log |
| DVXP1 | `https://ztsdvxp1.uksouth.kusto.windows.net` | Log |
| DVXP2 | `https://ztsdvxp2.uksouth.kusto.windows.net` | Log |
| PPE | `https://ztsppe.uksouth.kusto.windows.net` | Log |
| Stage | `https://ztsstage.westcentralus.kusto.windows.net` | Log |
| Stage2 | `https://ztsstage2.westcentralus.kusto.windows.net` | Log |
| Prod | `https://ztsprod.centralus.kusto.windows.net` | Log |

## Signal to Cluster Mapping

### By OccurringDeviceName / OccurringDatacenter

| Signal | Environment | Cluster |
|---|---|---|
| `ztsprod` | Prod | ztsprod.centralus |
| `centralus` | Prod | ztsprod.centralus |
| `centraluseuap` | Prod | ztsprod.centralus |
| `eastus2euap` | Prod | ztsprod.centralus |
| `northeurope` | Prod | ztsprod.centralus |
| `francecentral` | Prod | ztsprod.centralus |
| `ztsprod_{region}_resourceprovider` | Prod | ztsprod.centralus |
| `ZtsTipJobGroup-{region}` | Prod | ztsprod.centralus |
| `USEast2` (with eastus2euap in title) | Prod | ztsprod.centralus |
| `ztsstage` / `westcentralus` | Stage | ztsstage.westcentralus |
| `eastasia` (stage env) | Stage | ztsstage.westcentralus |
| `ztsppe` / `uksouth` | PPE | ztsppe.uksouth |
| `ztsdev` / `westus3` | Dev | ztsdev.westus3 |
| `ztsdvx1` | DVX1 | ztsdvx1.uksouth |
| `ztsdvx2` | DVX2 | ztsdvx2.uksouth |
| `ztsdvx3` | DVX3 | ztsdvx3.uksouth |
| `ztsdvxp1` | DVXP1 | ztsdvxp1.uksouth |
| `ztsdvxp2` | DVXP2 | ztsdvxp2.uksouth |
| `ztsstage2` | Stage2 | ztsstage2.westcentralus |

### Default

If no mapping matches: try Prod first (most ICMs are production), then ask the user. Update this file with the new mapping.

## Prod Regions

Deployment order: `eastus2euap` -> `centraluseuap` -> `francecentral` -> `northeurope` -> `centralus`

All prod regions log to the single Prod cluster. `centralus` and `centraluseuap` are different regions with separate CCG API instances and Synapse databases.

EUAP regions (`eastus2euap`, `centraluseuap`) are canary regions with frequent transient infrastructure failures.

## CCG API Endpoints

| Region | Endpoint | Synapse Server |
|---|---|---|
| eastus2euap | `ccg-api.services-eastus2euap.svc.cluster.local` | `zts-prod-eastus2euap.sql.azuresynapse.net` |
| centralus | `ccg-api.services-centralus.svc.cluster.local` | `zts-prod-centralus.sql.azuresynapse.net` |
| northeurope | `ccg-api.services-northeurope.svc.cluster.local` | TBD |
| francecentral | `ccg-api.services-francecentral.svc.cluster.local` | TBD |
| centraluseuap | `ccg-api.services-centraluseuap.svc.cluster.local` | TBD |
| eastasia (stage) | `ccg-api.services-eastasia.svc.cluster.local` | `zts-stage-eastasia.sql.azuresynapse.net` |

CCG API paths: `/get_graph`, `/get_ip2vmannot`, `/get_microseg`, `/start_pipeline_engine`, `/clean_run`

Synapse databases: `metadb` (run metadata), `graphdb` (output tables)

## TIP Test Resources

| Environment | Subscription | RG Pattern |
|---|---|---|
| Prod | `99f253a6-d303-4444-b794-b1bd853d86d7` | `zts-prod-{region}-tip-test-resources` |
| Stage | `e23493a6-48b3-4902-8daa-bea2c272f474` | `zts-stage-{region}-tip-test-resources` |
