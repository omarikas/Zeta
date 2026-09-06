import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';

// Offline stand-in for ClmMetricsController.getAvailablePresentations (@wire in
// clmVisitPresentations). Reuses the CLM presentations REST list; the Apex scopes
// by visit/territory but the visit-agnostic list is a safe offline approximation.
export default makeDualApex(() =>
    plannerApiFetch('/services/apexrest/clm/v1/presentations')
);
