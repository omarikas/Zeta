import { makeDualApex } from './_wireAdapter.js';

// Mirrors AccountAffiliationController.getAccountAffiliations, which returns an
// empty graph org-wide (feature not yet populated). Offline matches that.
export default makeDualApex(() => ({ nodes: [], edges: [], totalCount: 0 }));
