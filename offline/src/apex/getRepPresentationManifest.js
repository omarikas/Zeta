import { plannerApiFetch } from './restHelper.js';

// Read-only offline stand-in for ClmMetricsController.getRepPresentationManifest
// (which is Aura-only and not exposed over REST). Rebuilds the manifest the
// offline player needs by querying standard objects via the Salesforce REST
// Query API — no writes, no Apex deploy required. In real Lightning the same
// @salesforce/apex import resolves to the actual Apex method instead.
const API_VERSION = 'v62.0';

async function soql(query) {
    const path = `/services/data/${API_VERSION}/query?q=${encodeURIComponent(query)}`;
    const result = await plannerApiFetch(path);
    return (result && Array.isArray(result.records)) ? result.records : [];
}

export default async function getRepPresentationManifest() {
    // 1. Available presentations (mirrors the controller's field list; territory
    //    and date-window filtering are intentionally not replicated — cache all
    //    Available presentations).
    const presentations = await soql(
        "SELECT Id, Name, Status__c, Format__c, Product__r.Name, Slide_Count__c, " +
        "Tags__c, Content_Document_Id__c FROM CLM_Presentation__c " +
        "WHERE Status__c = 'Available' ORDER BY Name ASC"
    );

    const entries = presentations.map((p) => ({
        id: p.Id,
        presentationId: p.Id, // keyPath for the IndexedDB `manifest` store
        name: p.Name,
        status: p.Status__c,
        formatType: p.Format__c,
        productName: p.Product__r ? p.Product__r.Name : null,
        slideCount: p.Slide_Count__c != null ? Number(p.Slide_Count__c) : 0,
        tags: p.Tags__c,
        imageUrl: null,
        contentDocumentId: p.Content_Document_Id__c || null,
        contentVersionId: null,
        contentSize: null,
        sequences: [] // PDF-only cache depth; player renders PDF pages directly
    }));

    // 2. Sequences (slide list) — the player derives slide count + PDF page
    //    numbers from these. Kept minimal (no slideImageUrl) so PDFs render via
    //    the pdf.js canvas path, which works offline.
    const presIds = entries.map((e) => e.id).filter(Boolean);
    if (presIds.length) {
        const inPres = presIds.map((idv) => `'${idv}'`).join(',');
        const seqRows = await soql(
            "SELECT Id, CLM_Presentation__c, Sequence_Order__c, Sequence_Name__c, " +
            "Page_Number__c FROM CLM_Sequence__c " +
            `WHERE CLM_Presentation__c IN (${inPres}) ORDER BY Sequence_Order__c ASC NULLS LAST`
        );
        const byPres = {};
        for (const s of seqRows) {
            (byPres[s.CLM_Presentation__c] = byPres[s.CLM_Presentation__c] || []).push({
                id: s.Id,
                sequenceOrder: s.Sequence_Order__c != null ? Number(s.Sequence_Order__c) : null,
                sequenceName: s.Sequence_Name__c,
                pageNumber: s.Page_Number__c != null ? Number(s.Page_Number__c) : null
            });
        }
        for (const entry of entries) {
            const seqs = byPres[entry.id];
            if (seqs && seqs.length) {
                entry.sequences = seqs;
            } else if (entry.slideCount > 0) {
                // Fallback: synthesize one sequence per page from Slide_Count__c.
                entry.sequences = Array.from({ length: entry.slideCount }, (_, i) => ({
                    id: `${entry.id}-p${i + 1}`,
                    sequenceOrder: i + 1,
                    sequenceName: `Slide ${i + 1}`,
                    pageNumber: i + 1
                }));
            }
        }
    }

    // 3. Resolve latest ContentVersion (id + size) for each content document.
    const docIds = entries.map((e) => e.contentDocumentId).filter(Boolean);
    if (docIds.length) {
        const inList = docIds.map((idv) => `'${idv}'`).join(',');
        const versions = await soql(
            `SELECT Id, ContentDocumentId, ContentSize FROM ContentVersion ` +
            `WHERE ContentDocumentId IN (${inList}) AND IsLatest = true`
        );
        const byDoc = {};
        for (const v of versions) {
            byDoc[v.ContentDocumentId] = v;
        }
        for (const entry of entries) {
            const v = byDoc[entry.contentDocumentId];
            if (v) {
                entry.contentVersionId = v.Id;
                entry.contentSize = v.ContentSize != null ? Number(v.ContentSize) : null;
            }
        }
    }

    return entries;
}
