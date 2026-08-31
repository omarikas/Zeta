import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getCsvTemplate from '@salesforce/apex/PharmacySalesDataAdminController.getCsvTemplate';
import previewSalesDataCsv from '@salesforce/apex/PharmacySalesDataAdminController.previewSalesDataCsv';
import importSalesDataCsv from '@salesforce/apex/PharmacySalesDataAdminController.importSalesDataCsv';
import getWithdrawalRows from '@salesforce/apex/PharmacySalesDataAdminController.getWithdrawalRows';
import getImportBatches from '@salesforce/apex/PharmacySalesDataAdminController.getImportBatches';
import deleteWithdrawalRows from '@salesforce/apex/PharmacySalesDataAdminController.deleteWithdrawalRows';
import seedDemoData from '@salesforce/apex/PharmacySalesDataAdminController.seedDemoData';

const TABS = [
    { id: 'import', label: 'Import' },
    { id: 'viewer', label: 'Viewer' }
];

export default class PharmacySalesDataAdmin extends LightningElement {
    @track activeTab = 'import';
    @track csvContent = '';
    @track fileName = '';
    @track previewRows = [];
    @track importResult;
    @track isImporting = false;
    @track isPreviewing = false;
    @track viewerRows = [];
    @track batchRows = [];
    @track selectedViewerRows = [];

    viewerColumns = [
        { label: 'Month', fieldName: 'reportMonth', type: 'text' },
        { label: 'Source', fieldName: 'dataSource', type: 'text' },
        { label: 'Pharmacy', fieldName: 'pharmacyName', type: 'text' },
        { label: 'Brick', fieldName: 'brickName', type: 'text' },
        { label: 'Product', fieldName: 'productName', type: 'text' },
        { label: 'Qty', fieldName: 'quantity', type: 'number' },
        { label: 'Revenue', fieldName: 'revenue', type: 'currency', typeAttributes: { currencyCode: 'EGP' } }
    ];

    batchColumns = [
        { label: 'File', fieldName: 'fileName', type: 'text' },
        { label: 'Inserted', fieldName: 'rowsInserted', type: 'number' },
        { label: 'Updated', fieldName: 'rowsUpdated', type: 'number' },
        { label: 'Failed', fieldName: 'rowsFailed', type: 'number' }
    ];

    get tabs() {
        return TABS.map((tab) => ({
            ...tab,
            className: `tab-btn${this.activeTab === tab.id ? ' tab-btn--active' : ''}`
        }));
    }

    get isImportTab() {
        return this.activeTab === 'import';
    }

    get isViewerTab() {
        return this.activeTab === 'viewer';
    }

    get hasPreview() {
        return this.previewRows.length > 0;
    }

    get hasImportResult() {
        return Boolean(this.importResult);
    }

    connectedCallback() {
        this.loadViewerData();
    }

    handleTabClick(event) {
        this.activeTab = event.currentTarget.dataset.tabId;
        if (this.activeTab === 'viewer') {
            this.loadViewerData();
        }
    }

    async handleDownloadTemplate() {
        try {
            const template = await getCsvTemplate();
            this.downloadTextFile('pharmacy_sales_template.csv', template);
        } catch (error) {
            this.toast('Template error', this.reduceError(error), 'error');
        }
    }

    async handleFileChange(event) {
        const file = event.target.files?.[0];
        if (!file) {
            return;
        }
        this.fileName = file.name;
        try {
            this.csvContent = await file.text();
            await this.runPreview();
        } catch (error) {
            this.toast('File read error', this.reduceError(error), 'error');
        }
    }

    async runPreview() {
        if (!this.csvContent) {
            return;
        }
        this.isPreviewing = true;
        try {
            const result = await previewSalesDataCsv({ csvContent: this.csvContent });
            this.previewRows = result.previewRows || [];
            this.importResult = null;
        } catch (error) {
            this.toast('Preview error', this.reduceError(error), 'error');
        } finally {
            this.isPreviewing = false;
        }
    }

    async handleImport() {
        if (!this.csvContent) {
            this.toast('Import', 'Choose a CSV file first.', 'warning');
            return;
        }
        this.isImporting = true;
        try {
            this.importResult = await importSalesDataCsv({
                csvContent: this.csvContent,
                fileName: this.fileName
            });
            this.toast(
                'Import complete',
                `${this.importResult.rowsInserted} inserted, ${this.importResult.rowsUpdated} updated, ${this.importResult.rowsFailed} failed.`,
                this.importResult.rowsFailed > 0 ? 'warning' : 'success'
            );
            await this.loadViewerData();
        } catch (error) {
            this.toast('Import error', this.reduceError(error), 'error');
        } finally {
            this.isImporting = false;
        }
    }

    async loadViewerData() {
        try {
            this.viewerRows = await getWithdrawalRows({
                startMonth: null,
                endMonth: null,
                dataSource: 'All',
                brickId: null,
                rowLimit: 200
            });
            this.batchRows = await getImportBatches({ rowLimit: 20 });
        } catch (error) {
            this.toast('Viewer error', this.reduceError(error), 'error');
        }
    }

    handleViewerSelection(event) {
        this.selectedViewerRows = event.detail.selectedRows.map((row) => row.recordId);
    }

    async handleDeleteSelected() {
        if (!this.selectedViewerRows.length) {
            this.toast('Delete', 'Select rows to delete.', 'warning');
            return;
        }
        try {
            await deleteWithdrawalRows({ recordIds: this.selectedViewerRows });
            this.selectedViewerRows = [];
            await this.loadViewerData();
            this.toast('Deleted', 'Selected withdrawal rows removed.', 'success');
        } catch (error) {
            this.toast('Delete error', this.reduceError(error), 'error');
        }
    }

    async handleSeedDemo() {
        try {
            const result = await seedDemoData();
            this.toast('Demo seed', result.message, 'success');
            await this.loadViewerData();
        } catch (error) {
            this.toast('Seed error', this.reduceError(error), 'error');
        }
    }

    handleDownloadErrorLog() {
        if (!this.importResult?.errorLog) {
            return;
        }
        this.downloadTextFile('import_errors.txt', this.importResult.errorLog);
    }

    downloadTextFile(fileName, content) {
        const blob = new Blob([content], { type: 'text/plain;charset=utf-8' });
        const url = URL.createObjectURL(blob);
        const anchor = document.createElement('a');
        anchor.href = url;
        anchor.download = fileName;
        anchor.click();
        URL.revokeObjectURL(url);
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    reduceError(error) {
        return error?.body?.message || error?.message || 'Unknown error';
    }
}