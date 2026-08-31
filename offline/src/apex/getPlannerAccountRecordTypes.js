import { plannerApiFetch } from './restHelper.js';

export default async function getPlannerAccountRecordTypes() {
    return plannerApiFetch('/services/apexrest/planner/v1/accounts/record-types');
}
