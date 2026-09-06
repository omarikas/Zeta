import { makeDualApex } from './_wireAdapter.js';

// Offline stand-in for ClmMetricsController.getVisitSessions (@wire in
// clmVisitPresentations). No offline CLM-session source per visit yet, so it
// resolves empty — the component renders "no sessions" rather than erroring.
export default makeDualApex(() => []);
