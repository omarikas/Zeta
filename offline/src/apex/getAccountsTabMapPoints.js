import { plannerApiFetch } from './restHelper';
import { buildQuery } from './getAccountsTabPage';

const PATH = '/services/apexrest/planner/v1/accounts-tab/map-points';

export default async function getAccountsTabMapPoints(params) {
    return plannerApiFetch(`${PATH}${buildQuery(params)}`, { method: 'GET' });
}