import { plannerApiFetch } from './restHelper';

const PATH = '/services/apexrest/planner/v1/accounts-tab/page';

function buildQuery(params) {
    const qs = new URLSearchParams();
    const source = params || {};
    Object.keys(source).forEach((key) => {
        const value = source[key];
        if (value == null) {
            return;
        }
        if (Array.isArray(value)) {
            if (value.length) {
                qs.set(key, value.join(','));
            }
            return;
        }
        if (typeof value !== 'object') {
            qs.set(key, String(value));
        }
    });
    const encoded = qs.toString();
    return encoded ? `?${encoded}` : '';
}

export default async function getAccountsTabPage(params) {
    return plannerApiFetch(`${PATH}${buildQuery(params)}`, { method: 'GET' });
}

export { buildQuery };