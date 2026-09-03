import { plannerApiFetch } from './restHelper.js';

export default async function getRepPresentations() {
    return plannerApiFetch('/services/apexrest/clm/v1/presentations');
}
