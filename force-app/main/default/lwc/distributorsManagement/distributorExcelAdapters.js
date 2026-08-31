/**
 * Client-side Excel normalizers for distributor sales files (SheetJS workbook).
 * Each adapter returns { rows, warnings, sheetUsed, distributorCode, reportCadence }
 * where rows match Apex ingest shape.
 */

function cell(row, key) {
    if (!row || key == null) return '';
    const v = row[key];
    return v == null ? '' : String(v).trim();
}

function num(row, key) {
    const v = row[key];
    if (v == null || v === '') return null;
    const n = Number(v);
    return Number.isFinite(n) ? n : null;
}

function findHeaderRow(matrix, requiredHints) {
    for (let i = 0; i < Math.min(matrix.length, 25); i++) {
        const row = matrix[i].map((c) => (c == null ? '' : String(c).trim()));
        const lower = row.map((c) => c.toLowerCase());
        let hits = 0;
        for (const hint of requiredHints) {
            if (lower.some((c) => c.includes(hint.toLowerCase()))) hits++;
        }
        if (hits >= Math.min(2, requiredHints.length)) {
            return i;
        }
    }
    return -1;
}

function matrixToObjects(matrix, headerIndex) {
    const headers = matrix[headerIndex].map((c) => (c == null ? '' : String(c).trim()));
    const rows = [];
    for (let i = headerIndex + 1; i < matrix.length; i++) {
        const line = matrix[i];
        if (!line || line.every((c) => c == null || String(c).trim() === '')) continue;
        const obj = {};
        headers.forEach((h, idx) => {
            if (h) obj[h] = line[idx];
        });
        rows.push(obj);
    }
    return rows;
}

function getXlsx() {
    // eslint-disable-next-line no-undef
    const x = typeof XLSX !== 'undefined' ? XLSX : globalThis.XLSX || window.XLSX;
    if (!x) {
        throw new Error('SheetJS is not loaded.');
    }
    return x;
}

function sheetToMatrix(workbook, sheetName) {
    const sheet = workbook.Sheets[sheetName];
    if (!sheet) return [];
    return getXlsx().utils.sheet_to_json(sheet, { header: 1, defval: null, raw: false });
}

function pickSheet(workbook, predicates) {
    for (const name of workbook.SheetNames) {
        for (const pred of predicates) {
            if (pred(name)) return name;
        }
    }
    return workbook.SheetNames[0];
}

function sheetNamesBlob(workbook) {
    return (workbook?.SheetNames || []).join(' | ').toLowerCase();
}

function headerBlob(workbook, maxSheets = 4) {
    const parts = [];
    for (const name of (workbook?.SheetNames || []).slice(0, maxSheets)) {
        const matrix = sheetToMatrix(workbook, name);
        if (!matrix.length) continue;
        const headerIdx = Math.min(2, matrix.length - 1);
        for (let i = 0; i <= headerIdx; i++) {
            parts.push(
                (matrix[i] || [])
                    .map((c) => (c == null ? '' : String(c)))
                    .join(' ')
                    .toLowerCase()
            );
        }
    }
    return parts.join(' | ');
}

export const DISTRIBUTOR_OPTIONS = [
    { label: 'IBNSINA', value: 'IBNSINA' },
    { label: 'Sofico', value: 'Sofico' },
    { label: 'Egydrug', value: 'Egydrug' },
    { label: 'POS', value: 'POS' },
    { label: 'Elezaby', value: 'Elezaby' },
    { label: 'EPDA', value: 'EPDA' }
];

export const REPORT_CADENCE_OPTIONS = [
    { label: 'Auto-detect', value: '' },
    { label: 'Monthly', value: 'Monthly' },
    { label: 'Weekly', value: 'Weekly' }
];

export function detectDistributor(fileName) {
    const n = (fileName || '').toLowerCase();
    if (n.includes('ibn') || n.includes('ibnsina')) return 'IBNSINA';
    if (n.includes('sofico')) return 'Sofico';
    if (n.includes('egydrug') || n.includes('egydurg')) return 'Egydrug';
    if (n.includes('elezaby') || n.includes('ezzaby') || n.includes('ezzabi')) return 'Elezaby';
    if (n.includes('ebda') || n.includes('epda')) return 'EPDA';
    if (n.includes('pos') || n.includes('customer sales') || n.includes('tender sales')) return 'POS';
    return '';
}

/**
 * Detect distributor from workbook sheet names / header fingerprints.
 * Needed because many native files are named only "ZETA PHARM ...".
 */
export function detectDistributorFromWorkbook(workbook) {
    const sheets = sheetNamesBlob(workbook);
    const headers = headerBlob(workbook);

    if (
        sheets.includes('pharmacy sales') ||
        sheets.includes('branches sales') ||
        headers.includes('egydrug_customer_type') ||
        (headers.includes('item_code') && headers.includes('customer_code') && headers.includes('qty_invoice'))
    ) {
        return 'Egydrug';
    }
    if (
        sheets.includes('salesbyclient') ||
        (headers.includes('item code') && headers.includes('client code') && headers.includes('brick'))
    ) {
        return 'IBNSINA';
    }
    if (
        headers.includes('itemide') ||
        headers.includes('soldqty') ||
        headers.includes('iqvibrickcode') ||
        (sheets.includes('zeta') && headers.includes('customercode'))
    ) {
        return 'Sofico';
    }
    if (headers.includes('ean11') && headers.includes('branch name')) {
        return 'Elezaby';
    }
    if (headers.includes('mat. code') || headers.includes('mat code') || headers.includes('sal. district')) {
        return 'POS';
    }
    return '';
}

export function detectReportCadence(workbook, fileName) {
    const sheets = sheetNamesBlob(workbook);
    const n = (fileName || '').toLowerCase();
    if (
        sheets.includes('monthly stocks') ||
        sheets.includes('total monthly') ||
        n.includes('monthly')
    ) {
        return 'Monthly';
    }
    if (
        sheets.includes('current stock') ||
        sheets.includes('total daily') ||
        n.includes('weekly') ||
        n.includes('daily')
    ) {
        return 'Weekly';
    }
    return '';
}

export function parseDistributorWorkbook(workbook, distributorCode, fileName) {
    const fromName = detectDistributor(fileName);
    const fromContent = detectDistributorFromWorkbook(workbook);
    const code = distributorCode || fromName || fromContent;
    const reportCadence = detectReportCadence(workbook, fileName);
    let result;
    switch (code) {
        case 'IBNSINA':
            result = parseIbnsina(workbook);
            break;
        case 'Sofico':
            result = parseSofico(workbook);
            break;
        case 'Egydrug':
            result = parseEgydrug(workbook);
            break;
        case 'POS':
            result = parsePos(workbook);
            break;
        case 'Elezaby':
            result = parseElezaby(workbook);
            break;
        case 'EPDA':
        case 'Ebda':
            result = parseEpda(workbook);
            break;
        default:
            result = {
                rows: [],
                warnings: [
                    'Could not detect distributor from file name or sheet layout. Select a distributor and try again.'
                ],
                sheetUsed: null,
                distributorCode: ''
            };
    }
    result.reportCadence = reportCadence;
    result.detectedFrom = distributorCode ? 'manual' : fromName ? 'filename' : fromContent ? 'workbook' : 'none';
    if (reportCadence) {
        result.warnings = result.warnings || [];
        // informational only - cadence does not change the sales-sheet parser
        if (!result.warnings.some((w) => /cadence/i.test(w))) {
            result.warnings.push(`Detected report cadence: ${reportCadence} (sales sheets use the same layout).`);
        }
    }
    return result;
}

function parseIbnsina(workbook) {
    const warnings = [];
    const sheetName = pickSheet(workbook, [
        (n) => /salesbyclient/i.test(n),
        (n) => /client/i.test(n) && !/tender/i.test(n),
        (n) => /weekly|monthly/i.test(n)
    ]);
    let chosen = sheetName;
    for (const n of workbook.SheetNames) {
        if (/salesbyclient/i.test(n) && !/tender/i.test(n)) {
            chosen = n;
            break;
        }
    }
    const matrix = sheetToMatrix(workbook, chosen);
    const headerIdx = findHeaderRow(matrix, ['item code', 'client']);
    if (headerIdx < 0) {
        return {
            rows: [],
            warnings: ['IBNSINA: could not find client sales header.'],
            sheetUsed: chosen,
            distributorCode: 'IBNSINA'
        };
    }
    const objects = matrixToObjects(matrix, headerIdx);
    const rows = [];
    for (const o of objects) {
        const itemCode = cell(o, 'Item Code') || cell(o, 'Item code');
        const clientCode = cell(o, 'Client Code') || cell(o, 'Client code');
        if (!itemCode || !clientCode) continue;
        rows.push({
            distributorCode: 'IBNSINA',
            itemCode,
            itemName: cell(o, 'Item Name') || cell(o, 'Item name'),
            clientCode,
            clientName: cell(o, 'Client Name'),
            address: cell(o, 'Address_En') || cell(o, 'Address_Ar') || cell(o, 'Address'),
            governorate: cell(o, 'Governorate Name'),
            brickCode: cell(o, 'Brick'),
            brickName: cell(o, 'Brick Name'),
            quantity: num(o, 'Total Quantity') || num(o, 'Net'),
            revenue: num(o, 'Net'),
            unitPrice: null,
            reportMonth: cell(o, 'Date'),
            transactionDate: cell(o, 'Date')
        });
    }
    if (!rows.length) warnings.push('IBNSINA: no data rows parsed.');
    return { rows, warnings, sheetUsed: chosen, distributorCode: 'IBNSINA' };
}

function parseSofico(workbook) {
    const warnings = [];
    const chosen = pickSheet(workbook, [(n) => /zeta/i.test(n), (n) => /sales|cust/i.test(n)]);
    const matrix = sheetToMatrix(workbook, chosen);
    const headerIdx = findHeaderRow(matrix, ['customer', 'item']);
    if (headerIdx < 0) {
        return {
            rows: [],
            warnings: ['Sofico: could not find sales header (stock files are unsupported).'],
            sheetUsed: chosen,
            distributorCode: 'Sofico'
        };
    }
    const headers = matrix[headerIdx].map((c) => (c == null ? '' : String(c).trim()));
    if (headers.includes('Material Desc.') && !headers.includes('CUSTOMERCODE') && !headers.includes('CUSTOMERNAME')) {
        return {
            rows: [],
            warnings: ['Sofico STOCK sheet is not supported for sell-out import.'],
            sheetUsed: chosen,
            distributorCode: 'Sofico'
        };
    }
    const objects = matrixToObjects(matrix, headerIdx);
    const rows = [];
    for (const o of objects) {
        const itemCode = cell(o, 'ITEMIDE') || cell(o, 'ITEMID');
        const clientCode = cell(o, 'CUSTOMERCODE') || cell(o, 'ORDERACCOUNT');
        if (!itemCode || !clientCode) continue;
        rows.push({
            distributorCode: 'Sofico',
            itemCode,
            itemName: cell(o, 'ITEMNAME'),
            clientCode,
            clientName: cell(o, 'CUSTOMERNAME') || cell(o, 'CUSTOMERNAME0013'),
            address: cell(o, 'ADDRESS') || cell(o, 'ADDRESSSHIP'),
            governorate: cell(o, 'GOVER'),
            brickCode: cell(o, 'IQVIBRICKCODE'),
            brickName: cell(o, 'IQVIBRICKCODE'),
            quantity: num(o, 'SOLDQTY') || num(o, 'NET SALES'),
            revenue: num(o, 'TOTALVALUE'),
            unitPrice: num(o, 'SALESPIRCE') || num(o, 'SALESPIRCE2'),
            reportMonth: cell(o, 'BILLINGDATE') || cell(o, 'FROMDATE'),
            transactionDate: cell(o, 'BILLINGDATE')
        });
    }
    if (!rows.length) warnings.push('Sofico: no data rows parsed.');
    return { rows, warnings, sheetUsed: chosen, distributorCode: 'Sofico' };
}

function parseEgydrugSheet(workbook, sheetName) {
    const matrix = sheetToMatrix(workbook, sheetName);
    const headerIdx = findHeaderRow(matrix, ['item_code', 'customer']);
    if (headerIdx < 0) {
        return { rows: [], warning: `Egydrug: header not found on ${sheetName}.` };
    }
    const objects = matrixToObjects(matrix, headerIdx);
    const rows = [];
    for (const o of objects) {
        const itemCode = cell(o, 'ITEM_CODE');
        // Prefer pharmacy/customer; fall back to branch as sellout point when needed
        const clientCode =
            cell(o, 'CUSTOMER_CODE') || cell(o, 'BRANCH_CODE') || cell(o, 'COMPANY_ENTITY_CODE');
        if (!itemCode || !clientCode) continue;
        const qtyInvoice = num(o, 'QTY_INVOICE');
        const returnQty = num(o, 'RETURN_QTY') || 0;
        const qtyPack = num(o, 'QTY_PACK');
        let quantity = qtyInvoice != null ? qtyInvoice : qtyPack;
        if (quantity == null && returnQty) {
            quantity = returnQty;
        }
        rows.push({
            distributorCode: 'Egydrug',
            itemCode,
            itemName: cell(o, 'ITEM_NAME') || cell(o, 'ITEM_NAME_ENG'),
            clientCode,
            clientName: cell(o, 'CUSTOMER_NAME') || cell(o, 'BRANCH_NAME'),
            address: cell(o, 'CUSTOMER_ADDRESS') || '',
            governorate: cleanEgydrugPlace(cell(o, 'PROVINCE_NAME')),
            brickCode: cell(o, 'BRANCH_CODE') || '',
            brickName: cell(o, 'BRANCH_NAME') || '',
            quantity,
            revenue: num(o, 'TOTAL_VALUE_INVOICE') || num(o, 'VALUE'),
            unitPrice: num(o, 'PHARMAIST_PRICE') || num(o, 'BASE_PRICE'),
            reportMonth: cell(o, 'INVOICE_DATE'),
            transactionDate: cell(o, 'INVOICE_DATE'),
            sourceSheet: sheetName
        });
    }
    return { rows, warning: rows.length ? null : `Egydrug: no data rows on ${sheetName}.` };
}

function cleanEgydrugPlace(v) {
    const s = (v || '').trim();
    if (!s || s === '0' || s === '-' || s.toLowerCase() === 'null' || s.toLowerCase() === 'n/a') {
        return '';
    }
    return s;
}

function parseEgydrug(workbook) {
    const warnings = [];
    const salesSheets = [];
    for (const n of workbook.SheetNames) {
        if (/^pharmacy sales$/i.test(n.trim()) || /^branches sales$/i.test(n.trim())) {
            salesSheets.push(n);
        }
    }
    // Prefer Branches Sales first (better addresses for geocoding), then Pharmacy Sales
    salesSheets.sort((a, b) => {
        const score = (n) => (/branches/i.test(n) ? 0 : 1);
        return score(a) - score(b);
    });
    if (!salesSheets.length) {
        return {
            rows: [],
            warnings: ['Egydrug: Pharmacy Sales / Branches Sales sheet not found.'],
            sheetUsed: null,
            distributorCode: 'Egydrug'
        };
    }
    const rows = [];
    for (const sheetName of salesSheets) {
        const parsed = parseEgydrugSheet(workbook, sheetName);
        if (parsed.warning) warnings.push(parsed.warning);
        rows.push(...parsed.rows);
    }
    if (!rows.length) warnings.push('Egydrug: no data rows parsed.');
    return {
        rows,
        warnings,
        sheetUsed: salesSheets.join(' + '),
        distributorCode: 'Egydrug'
    };
}

function parsePos(workbook) {
    const warnings = [];
    const chosen = pickSheet(workbook, [(n) => /data/i.test(n)]);
    const matrix = sheetToMatrix(workbook, chosen);
    const headerIdx = findHeaderRow(matrix, ['customer', 'mat']);
    if (headerIdx < 0) {
        return {
            rows: [],
            warnings: ['POS: customer sales header not found (stock/purchasing .xls may need conversion).'],
            sheetUsed: chosen,
            distributorCode: 'POS'
        };
    }
    const objects = matrixToObjects(matrix, headerIdx);
    const rows = [];
    for (const o of objects) {
        const itemCode = cell(o, 'Mat. Code') || cell(o, 'Mat Code');
        const clientCode = cell(o, 'Customer');
        if (!itemCode || !clientCode) continue;
        rows.push({
            distributorCode: 'POS',
            itemCode: itemCode.replace(/\s+/g, ''),
            itemName: cell(o, 'Mat. Desc.') || cell(o, 'Mat Desc.'),
            clientCode,
            clientName: cell(o, 'Customer Name'),
            address: cell(o, 'Customer Address'),
            governorate: cell(o, 'Sal. Dist. Desc.'),
            brickCode: cell(o, 'Sal. District'),
            brickName: cell(o, 'Sal. Dist. Desc.'),
            quantity: num(o, 'Qty'),
            revenue: num(o, 'Value'),
            unitPrice: null,
            reportMonth: cell(o, 'Invoice Date'),
            transactionDate: cell(o, 'Invoice Date')
        });
    }
    if (!rows.length) warnings.push('POS: no data rows parsed.');
    return { rows, warnings, sheetUsed: chosen, distributorCode: 'POS' };
}

function parseElezaby(workbook) {
    const warnings = [];
    const chosen = workbook.SheetNames[0];
    const matrix = sheetToMatrix(workbook, chosen);
    const headerIdx = findHeaderRow(matrix, ['branch', 'mat']);
    if (headerIdx < 0) {
        return {
            rows: [],
            warnings: ['Elezaby: header not found.'],
            sheetUsed: chosen,
            distributorCode: 'Elezaby'
        };
    }
    const objects = matrixToObjects(matrix, headerIdx);
    const rows = [];
    for (const o of objects) {
        const itemCode = cell(o, 'Ean11') || cell(o, 'EAN11');
        const clientCode = cell(o, 'Branch');
        if (!itemCode || !clientCode) continue;
        rows.push({
            distributorCode: 'Elezaby',
            itemCode,
            itemName: cell(o, 'Mat Desc') || cell(o, 'Mat Desc.'),
            clientCode,
            clientName: cell(o, 'Branch Name'),
            address: '',
            governorate: '',
            brickCode: clientCode,
            brickName: cell(o, 'Branch Name'),
            quantity: num(o, 'Qty'),
            revenue: num(o, 'Sales Measures.Sales') || num(o, 'Sales'),
            unitPrice: null,
            reportMonth: cell(o, 'Post Date'),
            transactionDate: cell(o, 'Post Date')
        });
    }
    if (!rows.length) warnings.push('Elezaby: no data rows (branch used as sellout point).');
    return { rows, warnings, sheetUsed: chosen, distributorCode: 'Elezaby' };
}

function parseEpda(workbook) {
    const warnings = ['EPDA layouts vary; parser uses best-effort column detection.'];
    for (const name of workbook.SheetNames) {
        const matrix = sheetToMatrix(workbook, name);
        const headerIdx = findHeaderRow(matrix, ['item', 'customer']);
        if (headerIdx < 0) continue;
        const objects = matrixToObjects(matrix, headerIdx);
        const headers = matrix[headerIdx].map((c) => (c == null ? '' : String(c).trim()));
        const itemKey =
            headers.find((h) => /item.*code|material|mat\.?\s*code/i.test(h)) ||
            headers.find((h) => /item/i.test(h));
        const nameKey = headers.find((h) => /item.*name|mat.*desc|material desc/i.test(h));
        const clientKey =
            headers.find((h) => /customer.*code|client.*code/i.test(h)) ||
            headers.find((h) => /customer|client/i.test(h));
        const clientNameKey = headers.find((h) => /customer.*name|client.*name/i.test(h));
        const addrKey = headers.find((h) => /address/i.test(h));
        const qtyKey = headers.find((h) => /qty|quantity|sold/i.test(h));
        if (!itemKey || !clientKey) continue;
        const rows = [];
        for (const o of objects) {
            const itemCode = cell(o, itemKey);
            const clientCode = cell(o, clientKey);
            if (!itemCode || !clientCode) continue;
            rows.push({
                distributorCode: 'EPDA',
                itemCode,
                itemName: nameKey ? cell(o, nameKey) : '',
                clientCode,
                clientName: clientNameKey ? cell(o, clientNameKey) : '',
                address: addrKey ? cell(o, addrKey) : '',
                governorate: '',
                brickCode: '',
                brickName: '',
                quantity: qtyKey ? num(o, qtyKey) : null,
                revenue: null,
                unitPrice: null,
                reportMonth: '',
                transactionDate: ''
            });
        }
        if (rows.length) {
            return { rows, warnings, sheetUsed: name, distributorCode: 'EPDA' };
        }
    }
    return {
        rows: [],
        warnings: ['EPDA: no recognizable sales sheet. Unpack nested zip and upload the sales workbook.'],
        sheetUsed: null,
        distributorCode: 'EPDA'
    };
}

/** Infer YYYY-MM from first row dates. */
export function inferReportMonth(rows) {
    for (const r of rows || []) {
        const d = r.reportMonth || r.transactionDate;
        if (!d) continue;
        const s = String(d);
        const m1 = s.match(/(20\d{2})[-\/](\d{1,2})/);
        if (m1) return `${m1[1]}-${String(m1[2]).padStart(2, '0')}`;
        const m2 = s.match(/(20\d{2})(\d{2})(\d{2})/);
        if (m2) return `${m2[1]}-${m2[2]}`;
        // Excel serial / loose "2026-6-28 12:29:24"
        const m3 = s.match(/(20\d{2})-(\d{1,2})-(\d{1,2})/);
        if (m3) return `${m3[1]}-${String(m3[2]).padStart(2, '0')}`;
    }
    const now = new Date();
    return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
}