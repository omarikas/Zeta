import { plannerApiFetch } from './restHelper';

const PATH = '/services/apexrest/planner/v1/accounts-tab/record-type-options';

export default async function getAccountsTabRecordTypeOptions() {
    return plannerApiFetch(PATH, { method: 'GET' });
}