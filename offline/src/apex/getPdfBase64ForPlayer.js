import { plannerApiFetch } from './restHelper.js';

export default async function getPdfBase64ForPlayer(params = {}) {
    const result = await plannerApiFetch('/services/apexrest/clm/v1/pdf-base64', {
        method: 'POST',
        body: JSON.stringify({ contentDocumentId: params.contentDocumentId })
    });
    return result?.base64 || null;
}
