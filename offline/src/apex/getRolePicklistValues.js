import { makeDualApex } from './_wireAdapter.js';

// Picklist options for the affiliation network filters. The graph is empty
// offline (mirrors the org), so options resolve empty rather than erroring.
export default makeDualApex(() => []);
