import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';

// Dual-mode: clmPlayer calls it imperatively; clmMessageFeedback consumes it via
// @wire. Same REST loader backs both paths.
export default makeDualApex((params = {}) =>
    plannerApiFetch('/services/apexrest/clm/v1/sessions/message-responses/fetch', {
        method: 'POST',
        body: JSON.stringify({ sessionId: params && params.sessionId })
    })
);
