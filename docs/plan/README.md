# Non-AI delivery plan

The user authorized completing all non-AI flows and adding Google/Facebook OAuth.
Implementation and review follow [the delivery contract](../active/NON_AI_DELIVERY.md).

| Task | Scope | State |
| --- | --- | --- |
| non-ai-baseline | Save recovery copy and return to pushed source without recent AI work | completed |
| non-ai-oauth | Configurable Google/Facebook, browser callback and password change | independently approved; live credentials pending |
| non-ai-backend | Persistent, authorized APIs and management integrity | developing |
| non-ai-frontend | Connect active user screens to real services/state | developing |
| non-ai-management-ui | Staff navigation, DTOs and management actions | developing |
| non-ai-review | Independent integration, regression and access-control verification | pending |

The user will register Google Cloud/Meta applications and provide credentials later.
The implementation must work without credentials for existing login methods; provider
acceptance is verified with controlled responses now and real credentials later.

