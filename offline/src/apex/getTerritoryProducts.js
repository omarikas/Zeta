import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';

// Offline stand-in for VisitCallReportController.getTerritoryProducts.
// The Apex scopes products by the user's territory hierarchy + PTA + ATPF. That
// territory logic can't be mirrored client-side, so this approximates it via the
// visit account's Account_Territory_Product_Fields__c (ATPF) rows joined to
// Product2 — the account's rated products, which is what the grids display.
const API_VERSION = 'v62.0';

async function soql(query) {
    const path = `/services/data/${API_VERSION}/query?q=${encodeURIComponent(query)}`;
    const result = await plannerApiFetch(path);
    return result && Array.isArray(result.records) ? result.records : [];
}

function quoteList(ids) {
    return ids.map((id) => `'${id}'`).join(',');
}

function mapProduct(p, atpf) {
    const parentName = p.Parent_Product__r ? p.Parent_Product__r.Name : null;
    const brandName = parentName || p.Primary_Brand__c || p.Name;
    return {
        productId: p.Id,
        productName: p.Name,
        imageUrl: p.Product_Image_URL__c || null,
        productType: p.Product_Type__c || null,
        parentProductId: p.Parent_Product__c || null,
        brandName,
        strength: p.Strength__c || null,
        form: p.Form__c || null,
        adoption: atpf ? atpf.Adoption__c : null,
        loyalty: atpf ? atpf.Loyalty__c : null,
        productMatrixRating: atpf ? atpf.Product_Matrix_Rating__c : null,
        targetVisitFrequency: atpf ? atpf.Target_Visit_Frequency__c : null,
        rxPerWeek: atpf ? atpf.Rx_Per_Week__c : null
    };
}

async function loadTerritoryProducts(params) {
    const visitId = params && params.visitId;
    if (!visitId) {
        return [];
    }

    const visitRows = await soql(
        `SELECT Account__c FROM Visit__c WHERE Id = '${visitId}' LIMIT 1`
    );
    const accountId = visitRows.length ? visitRows[0].Account__c : null;
    if (!accountId) {
        return [];
    }

    const atpfRows = await soql(
        'SELECT Product2_Id__c, Adoption__c, Loyalty__c, Product_Matrix_Rating__c, ' +
        'Target_Visit_Frequency__c, Rx_Per_Week__c ' +
        'FROM Account_Territory_Product_Fields__c ' +
        `WHERE Account__c = '${accountId}' AND Is_Active__c = TRUE`
    );
    const atpfByProduct = new Map();
    atpfRows.forEach((row) => {
        if (row.Product2_Id__c && !atpfByProduct.has(row.Product2_Id__c)) {
            atpfByProduct.set(row.Product2_Id__c, row);
        }
    });
    const productIds = Array.from(atpfByProduct.keys());
    if (!productIds.length) {
        return [];
    }

    const products = await soql(
        'SELECT Id, Name, Product_Image_URL__c, Product_Type__c, Parent_Product__c, ' +
        'Parent_Product__r.Name, Primary_Brand__c, Strength__c, Form__c ' +
        `FROM Product2 WHERE Id IN (${quoteList(productIds)}) AND IsActive = TRUE ORDER BY Name ASC`
    );

    return products.map((p) => mapProduct(p, atpfByProduct.get(p.Id)));
}

export default makeDualApex(loadTerritoryProducts);
