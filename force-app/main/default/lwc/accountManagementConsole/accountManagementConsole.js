import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { loadScript } from 'lightning/platformResourceLoader';
import SHEETJS from '@salesforce/resourceUrl/sheetjs';
import getCounts from '@salesforce/apex/AccountManagementController.getCounts';
import startWipe from '@salesforce/apex/AccountManagementController.startWipe';
import getWipeStatus from '@salesforce/apex/AccountManagementController.getWipeStatus';
import upsertOrganizationChunk from '@salesforce/apex/AccountManagementController.upsertOrganizationChunk';
import upsertDoctorChunk from '@salesforce/apex/AccountManagementController.upsertDoctorChunk';
import upsertAffiliationChunk from '@salesforce/apex/AccountManagementController.upsertAffiliationChunk';
import exportAccounts from '@salesforce/apex/AccountManagementController.exportAccounts';
import exportAffiliations from '@salesforce/apex/AccountManagementController.exportAffiliations';
import deactivateLink from '@salesforce/apex/AccountBusinessUnitService.deactivateLink';
import exportLinks from '@salesforce/apex/AccountBusinessUnitService.exportLinks';
import listBusinessUnitOptions from '@salesforce/apex/AccountBusinessUnitService.listBusinessUnitOptions';
import listForAccount from '@salesforce/apex/AccountBusinessUnitService.listForAccount';
import searchAccounts from '@salesforce/apex/AccountBusinessUnitService.searchAccounts';
import upsertLink from '@salesforce/apex/AccountBusinessUnitService.upsertLink';
import upsertLinks from '@salesforce/apex/AccountBusinessUnitService.upsertLinks';

const TABS = [
    { id: 'load', label: 'Wipe & Load' },
    { id: 'modify', label: 'Import / Modify' },
    { id: 'businessUnits', label: 'Business Units' },
    { id: 'export', label: 'Export' },
    { id: 'duplicates', label: 'Duplicate review' }
];

const CHUNK_SIZE = 150;
const POTENTIALITY_OPTIONS = [
    { label: '—', value: '' },
    { label: 'A', value: 'A' },
    { label: 'B', value: 'B' },
    { label: 'C', value: 'C' }
];
const PROPENSITY_OPTIONS = [
    { label: '—', value: '' },
    { label: '1', value: '1' },
    { label: '2', value: '2' },
    { label: '3', value: '3' }
];

export default class AccountManagementConsole extends LightningElement {
    @track activeTab = 'load';
    @track accountCount = 0;
    @track affiliationCount = 0;
    @track orgFileName = '';
    @track doctorFileName = '';
    @track orgRows = [];
    @track doctorRows = [];
    @track isBusy = false;
    @track progressMessage = '';
    @track progressPercent = 0;
    @track loadSummary = '';
    @track errorLines = [];
    @track duplicateHits = [];
    @track checkDuplicates = true;
    @track wipeJobId;
    @track buSearchTerm = '';
    @track buSearchResults = [];
    @track selectedBuAccountId;
    @track selectedBuAccountLabel = '';
    @track accountBuLinks = [];
    @track buOptions = [];
    @track selectedBuTerritoryId = '';
    @track linkPotentiality = '';
    @track linkPropensity = '';
    @track showInactiveBuLinks = true;
    @track buImportFileName = '';
    sheetjsReady = false;
    sheetjsLoading = false;

    get tabs() {
        return TABS.map((tab) => ({
            ...tab,
            className: `tab-btn${this.activeTab === tab.id ? ' tab-btn--active' : ''}`
        }));
    }

    get isLoadTab() {
        return this.activeTab === 'load';
    }
    get isModifyTab() {
        return this.activeTab === 'modify';
    }
    get isExportTab() {
        return this.activeTab === 'export';
    }
    get isBusinessUnitsTab() {
        return this.activeTab === 'businessUnits';
    }
    get isDuplicatesTab() {
        return this.activeTab === 'duplicates';
    }
    get hasSelectedBuAccount() {
        return !!this.selectedBuAccountId;
    }
    get hasAccountBuLinks() {
        return (this.accountBuLinks || []).length > 0;
    }
    get potentialityOptions() {
        return POTENTIALITY_OPTIONS;
    }
    get propensityOptions() {
        return PROPENSITY_OPTIONS;
    }
    get buOptionItems() {
        return (this.buOptions || []).map((option) => ({
            label: option.label,
            value: option.territory2Id
        }));
    }
    get canSaveBuLink() {
        return this.hasSelectedBuAccount && !!this.selectedBuTerritoryId && !this.isBusy;
    }
    get isBuSaveDisabled() {
        return !this.canSaveBuLink;
    }
    get hasErrors() {
        return this.errorLines.length > 0;
    }
    get hasDuplicates() {
        return this.duplicateHits.length > 0;
    }
    get hasOrgRows() {
        return this.orgRows.length > 0;
    }
    get hasDoctorRows() {
        return this.doctorRows.length > 0;
    }
    get orgRowCount() {
        return this.orgRows.length;
    }
    get doctorRowCount() {
        return this.doctorRows.length;
    }
    get progressStyle() {
        return `width:${this.progressPercent}%;`;
    }
    get canLoad() {
        return this.orgRows.length > 0 && this.doctorRows.length > 0 && !this.isBusy;
    }

    get wipeDisabled() {
        return !this.canLoad;
    }

    connectedCallback() {
        this.refreshCounts();
    }

    renderedCallback() {
        if (this.sheetjsReady || this.sheetjsLoading) {
            return;
        }
        this.sheetjsLoading = true;
        loadScript(this, SHEETJS)
            .then(() => {
                this.sheetjsReady = true;
            })
            .catch((error) => {
                this.sheetjsLoading = false;
                this.toast('SheetJS failed to load', this.reduceError(error), 'error');
            });
    }

    handleTabClick(event) {
        this.activeTab = event.currentTarget.dataset.tabId;
        if (this.activeTab === 'businessUnits' && !this.buOptions.length) {
            this.loadBuOptions();
        }
    }

    async loadBuOptions() {
        try {
            this.buOptions = await listBusinessUnitOptions();
        } catch (error) {
            this.toast('Business Unit options', this.reduceError(error), 'error');
        }
    }

    handleBuSearchChange(event) {
        this.buSearchTerm = event.target.value || '';
        this.debounceBuSearch();
    }

    debounceBuSearch() {
        clearTimeout(this.buSearchTimer);
        this.buSearchTimer = setTimeout(() => {
            this.runBuSearch();
        }, 350);
    }

    async runBuSearch() {
        const term = (this.buSearchTerm || '').trim();
        if (term.length < 2) {
            this.buSearchResults = [];
            return;
        }
        try {
            this.buSearchResults = await searchAccounts({ searchTerm: term });
        } catch (error) {
            this.toast('Account search', this.reduceError(error), 'error');
        }
    }

    async handleBuAccountPick(event) {
        const accountId = event.currentTarget.dataset.id;
        const hit = (this.buSearchResults || []).find((row) => row.accountId === accountId);
        if (!hit) {
            return;
        }
        this.selectedBuAccountId = hit.accountId;
        this.selectedBuAccountLabel = [hit.name, hit.externalId, hit.city]
            .filter(Boolean)
            .join(' · ');
        this.buSearchResults = [];
        this.buSearchTerm = hit.name || '';
        await this.refreshAccountBuLinks();
    }

    async refreshAccountBuLinks() {
        if (!this.selectedBuAccountId) {
            this.accountBuLinks = [];
            return;
        }
        try {
            this.accountBuLinks = await listForAccount({
                accountId: this.selectedBuAccountId,
                includeInactive: this.showInactiveBuLinks
            });
        } catch (error) {
            this.toast('Load links', this.reduceError(error), 'error');
        }
    }

    handleShowInactiveBuLinksChange(event) {
        this.showInactiveBuLinks = event.target.checked;
        this.refreshAccountBuLinks();
    }

    handleBuTerritoryChange(event) {
        this.selectedBuTerritoryId = event.detail.value;
    }

    handleLinkPotentialityChange(event) {
        this.linkPotentiality = event.detail.value;
    }

    handleLinkPropensityChange(event) {
        this.linkPropensity = event.detail.value;
    }

    async handleSaveBuLink() {
        if (!this.canSaveBuLink) {
            return;
        }
        this.isBusy = true;
        try {
            await upsertLink({
                request: {
                    accountId: this.selectedBuAccountId,
                    businessUnitTerritory2Id: this.selectedBuTerritoryId,
                    potentiality: this.linkPotentiality || null,
                    propensity: this.linkPropensity || null,
                    isActive: true
                }
            });
            this.selectedBuTerritoryId = '';
            this.linkPotentiality = '';
            this.linkPropensity = '';
            await this.refreshAccountBuLinks();
            this.toast('Saved', 'Account Business Unit link saved.', 'success');
        } catch (error) {
            this.toast('Save failed', this.reduceError(error), 'error');
        } finally {
            this.isBusy = false;
        }
    }

    async handleDeactivateBuLink(event) {
        const linkId = event.currentTarget.dataset.id;
        if (!linkId || this.isBusy) {
            return;
        }
        this.isBusy = true;
        try {
            await deactivateLink({ linkId });
            await this.refreshAccountBuLinks();
            this.toast('Deactivated', 'Business Unit link deactivated.', 'success');
        } catch (error) {
            this.toast('Deactivate failed', this.reduceError(error), 'error');
        } finally {
            this.isBusy = false;
        }
    }

    async handleExportBuLinks() {
        this.isBusy = true;
        this.progressMessage = 'Exporting Account Business Units...';
        try {
            await this.ensureSheetJs();
            const links = [];
            let lastId = null;
            let hasMore = true;
            while (hasMore) {
                const page = await exportLinks({ lastId, pageSize: 500 });
                links.push(...(page.links || []));
                hasMore = page.hasMore;
                lastId = page.nextId;
            }
            const rows = links.map((link) => ({
                AccountExternalId: link.accountExternalId,
                BusinessUnitExternalId: link.businessUnitExternalId,
                Potentiality: link.potentiality,
                Propensity: link.propensity,
                IsActive: link.isActive,
                StartDate: link.startDate,
                EndDate: link.endDate
            }));
            const wb = window.XLSX.utils.book_new();
            window.XLSX.utils.book_append_sheet(
                wb,
                window.XLSX.utils.json_to_sheet(rows),
                'AccountBusinessUnits'
            );
            const out = window.XLSX.write(wb, { bookType: 'xlsx', type: 'array' });
            this.downloadBlob(
                'zeta_account_business_units.xlsx',
                new Blob([out], {
                    type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
                })
            );
            this.toast('Export complete', `${rows.length} links exported`, 'success');
        } catch (error) {
            this.toast('Export failed', this.reduceError(error), 'error');
        } finally {
            this.isBusy = false;
            this.progressMessage = '';
        }
    }

    async handleBuImportFile(event) {
        const file = event.target.files?.[0];
        if (!file) {
            return;
        }
        this.buImportFileName = file.name;
        this.isBusy = true;
        this.errorLines = [];
        try {
            await this.ensureSheetJs();
            const workbook = await this.readWorkbook(file);
            const sheet = workbook.Sheets[workbook.SheetNames[0]];
            const raw = window.XLSX.utils.sheet_to_json(sheet, { defval: null });
            const requests = raw
                .map((row) => this.mapBuImportRow(row))
                .filter((row) => row != null);
            let success = 0;
            let errors = 0;
            for (let i = 0; i < requests.length; i += CHUNK_SIZE) {
                const chunk = requests.slice(i, i + CHUNK_SIZE);
                const result = await upsertLinks({ requests: chunk });
                success += result.successCount || 0;
                errors += result.errorCount || 0;
                this.mergeErrors(result.errors);
            }
            this.toast(
                'Import complete',
                `${success} saved, ${errors} errors`,
                errors ? 'warning' : 'success'
            );
            if (this.selectedBuAccountId) {
                await this.refreshAccountBuLinks();
            }
        } catch (error) {
            this.toast('Import failed', this.reduceError(error), 'error');
        } finally {
            this.isBusy = false;
        }
    }

    mapBuImportRow(row) {
        const accountExternalId = this.asString(
            this.pick(row, [
                'AccountExternalId',
                'Account External Id',
                'Account_External_ID__c',
                'Account External ID'
            ])
        );
        const businessUnitExternalId = this.asString(
            this.pick(row, [
                'BusinessUnitExternalId',
                'Business Unit External Id',
                'Business_Unit_External_ID__c',
                'TERR_BU'
            ])
        );
        if (!accountExternalId || !businessUnitExternalId) {
            return null;
        }
        const activeRaw = this.pick(row, ['IsActive', 'Is Active', 'Is_Active__c']);
        return {
            accountExternalId,
            businessUnitExternalId,
            potentiality: this.asString(this.pick(row, ['Potentiality', 'Potentiality__c'])),
            propensity: this.asString(this.pick(row, ['Propensity', 'Propensity__c'])),
            isActive: activeRaw == null ? true : String(activeRaw).toLowerCase() !== 'false'
        };
    }

    async refreshCounts() {
        try {
            const counts = await getCounts();
            this.accountCount = counts.accountCount || 0;
            this.affiliationCount = counts.affiliationCount || 0;
        } catch (error) {
            this.toast('Count error', this.reduceError(error), 'error');
        }
    }

    handleCheckDuplicatesChange(event) {
        this.checkDuplicates = event.target.checked;
    }

    async handleOrgFile(event) {
        const file = event.target.files?.[0];
        if (!file) {
            return;
        }
        this.orgFileName = file.name;
        try {
            await this.ensureSheetJs();
            const workbook = await this.readWorkbook(file);
            const sheet = workbook.Sheets[workbook.SheetNames[0]];
            const raw = window.XLSX.utils.sheet_to_json(sheet, { defval: null });
            this.orgRows = raw.map((r) => this.mapOrgRow(r)).filter((r) => r);
            this.toast('Organizations loaded', `${this.orgRows.length} rows parsed`, 'success');
        } catch (error) {
            this.toast('Organizations parse error', this.reduceError(error), 'error');
        }
    }

    async handleDoctorFile(event) {
        const file = event.target.files?.[0];
        if (!file) {
            return;
        }
        this.doctorFileName = file.name;
        try {
            await this.ensureSheetJs();
            const workbook = await this.readWorkbook(file);
            const sheet = workbook.Sheets[workbook.SheetNames[0]];
            const raw = window.XLSX.utils.sheet_to_json(sheet, { defval: null });
            this.doctorRows = raw.map((r) => this.mapDoctorRow(r)).filter((r) => r);
            this.toast('Doctors loaded', `${this.doctorRows.length} rows parsed`, 'success');
        } catch (error) {
            this.toast('Doctors parse error', this.reduceError(error), 'error');
        }
    }

    async handleWipeAndLoad() {
        if (!this.canLoad) {
            return;
        }
        // eslint-disable-next-line no-alert
        const confirmed = window.confirm(
            `This will DELETE all ${this.accountCount} Accounts and ${this.affiliationCount} affiliations, then load from the selected Excel files. Continue?`
        );
        if (!confirmed) {
            return;
        }
        this.isBusy = true;
        this.errorLines = [];
        this.duplicateHits = [];
        this.loadSummary = '';
        try {
            this.progressMessage = 'Starting wipe...';
            this.progressPercent = 2;
            const wipe = await startWipe();
            this.wipeJobId = wipe.jobId;
            await this.pollWipe();
            this.progressMessage = 'Loading organizations...';
            const orgStats = await this.uploadOrgChunks(this.orgRows, this.checkDuplicates);
            this.progressMessage = 'Loading doctors...';
            const docStats = await this.uploadDoctorChunks(this.doctorRows, this.checkDuplicates);
            this.progressMessage = 'Loading affiliations...';
            const affRows = this.buildAffiliationRows(this.orgRows);
            const affStats = await this.uploadAffiliationChunks(affRows);
            this.progressPercent = 100;
            this.progressMessage = 'Complete';
            this.loadSummary = `Orgs ${orgStats.success}/${this.orgRows.length}, Doctors ${docStats.success}/${this.doctorRows.length}, Affiliations ${affStats.success}/${affRows.length}. Errors: ${orgStats.errors + docStats.errors + affStats.errors}.`;
            await this.refreshCounts();
            this.toast('Load complete', this.loadSummary, 'success');
        } catch (error) {
            this.toast('Load failed', this.reduceError(error), 'error');
            this.errorLines = [...this.errorLines, this.reduceError(error)];
        } finally {
            this.isBusy = false;
        }
    }

    async handleModifyImport() {
        if ((!this.orgRows.length && !this.doctorRows.length) || this.isBusy) {
            return;
        }
        this.isBusy = true;
        this.errorLines = [];
        this.duplicateHits = [];
        try {
            let orgStats = { success: 0, errors: 0 };
            let docStats = { success: 0, errors: 0 };
            let affStats = { success: 0, errors: 0 };
            if (this.orgRows.length) {
                this.progressMessage = 'Upserting organizations...';
                orgStats = await this.uploadOrgChunks(this.orgRows, this.checkDuplicates);
            }
            if (this.doctorRows.length) {
                this.progressMessage = 'Upserting doctors...';
                docStats = await this.uploadDoctorChunks(this.doctorRows, this.checkDuplicates);
            }
            if (this.orgRows.length && this.doctorRows.length) {
                this.progressMessage = 'Upserting affiliations...';
                affStats = await this.uploadAffiliationChunks(this.buildAffiliationRows(this.orgRows));
            }
            this.progressPercent = 100;
            this.loadSummary = `Modify complete. Orgs ${orgStats.success}, Doctors ${docStats.success}, Affiliations ${affStats.success}.`;
            await this.refreshCounts();
            this.toast('Import complete', this.loadSummary, 'success');
        } catch (error) {
            this.toast('Import failed', this.reduceError(error), 'error');
        } finally {
            this.isBusy = false;
        }
    }

    async handleExport() {
        this.isBusy = true;
        this.progressMessage = 'Exporting...';
        try {
            await this.ensureSheetJs();
            const accounts = [];
            let afterAccountId = null;
            let hasMore = true;
            while (hasMore) {
                const page = await exportAccounts({ afterId: afterAccountId, pageSize: 2000 });
                accounts.push(...(page.accounts || []));
                hasMore = page.hasMore;
                afterAccountId = page.nextAccountId;
                this.progressPercent = Math.min(90, Math.round((accounts.length / Math.max(this.accountCount, 1)) * 90));
            }

            const affiliations = [];
            let afterAffId = null;
            hasMore = true;
            while (hasMore) {
                const page = await exportAffiliations({ afterId: afterAffId, pageSize: 2000 });
                affiliations.push(...(page.affiliations || []));
                hasMore = page.hasMore;
                afterAffId = page.nextAffiliationId;
            }

            const wb = window.XLSX.utils.book_new();
            window.XLSX.utils.book_append_sheet(
                wb,
                window.XLSX.utils.json_to_sheet(accounts),
                'Accounts'
            );
            window.XLSX.utils.book_append_sheet(
                wb,
                window.XLSX.utils.json_to_sheet(affiliations),
                'Affiliations'
            );
            const out = window.XLSX.write(wb, { bookType: 'xlsx', type: 'array' });
            this.downloadBlob(
                'zeta_accounts_export.xlsx',
                new Blob([out], {
                    type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
                })
            );
            this.progressPercent = 100;
            this.progressMessage = `Exported ${accounts.length} accounts and ${affiliations.length} affiliations`;
            this.toast('Export complete', this.progressMessage, 'success');
        } catch (error) {
            this.toast('Export failed', this.reduceError(error), 'error');
        } finally {
            this.isBusy = false;
        }
    }

    async pollWipe() {
        let attempts = 0;
        while (attempts < 600) {
            attempts += 1;
            const status = await getWipeStatus({ jobId: this.wipeJobId });
            this.accountCount = status.accountCount || 0;
            this.affiliationCount = status.affiliationCount || 0;
            const processed = status.jobItemsProcessed || 0;
            const total = status.totalJobItems || 1;
            this.progressPercent = Math.min(35, 5 + Math.round((processed / total) * 30));
            this.progressMessage = `Wipe ${status.status || ''} � accounts left: ${this.accountCount}`;
            if (status.status === 'Completed' || (status.status !== 'Processing' && this.accountCount === 0)) {
                return;
            }
            if (status.status === 'Failed') {
                throw new Error(status.extendedStatus || 'Wipe failed');
            }
            await this.sleep(3000);
        }
        throw new Error('Wipe timed out');
    }

    async uploadOrgChunks(rows, checkDuplicates) {
        let success = 0;
        let errors = 0;
        const total = rows.length || 1;
        for (let i = 0; i < rows.length; i += CHUNK_SIZE) {
            const chunk = rows.slice(i, i + CHUNK_SIZE);
            const result = await upsertOrganizationChunk({
                rows: chunk,
                checkDuplicates: checkDuplicates && i === 0
            });
            success += result.successCount || 0;
            errors += result.errorCount || 0;
            this.mergeErrors(result.errors);
            this.mergeDuplicates(result.duplicates);
            this.progressPercent = 35 + Math.round(((i + chunk.length) / total) * 25);
            this.progressMessage = `Organizations ${i + chunk.length}/${rows.length}`;
        }
        return { success, errors };
    }

    async uploadDoctorChunks(rows, checkDuplicates) {
        let success = 0;
        let errors = 0;
        const total = rows.length || 1;
        for (let i = 0; i < rows.length; i += CHUNK_SIZE) {
            const chunk = rows.slice(i, i + CHUNK_SIZE);
            const result = await upsertDoctorChunk({
                rows: chunk,
                checkDuplicates: checkDuplicates && i === 0
            });
            success += result.successCount || 0;
            errors += result.errorCount || 0;
            this.mergeErrors(result.errors);
            this.mergeDuplicates(result.duplicates);
            this.progressPercent = 60 + Math.round(((i + chunk.length) / total) * 20);
            this.progressMessage = `Doctors ${i + chunk.length}/${rows.length}`;
        }
        return { success, errors };
    }

    async uploadAffiliationChunks(rows) {
        let success = 0;
        let errors = 0;
        const total = rows.length || 1;
        for (let i = 0; i < rows.length; i += CHUNK_SIZE) {
            const chunk = rows.slice(i, i + CHUNK_SIZE);
            const result = await upsertAffiliationChunk({ rows: chunk });
            success += result.successCount || 0;
            errors += result.errorCount || 0;
            this.mergeErrors(result.errors);
            this.progressPercent = 80 + Math.round(((i + chunk.length) / total) * 20);
            this.progressMessage = `Affiliations ${i + chunk.length}/${rows.length}`;
        }
        return { success, errors };
    }

    buildAffiliationRows(orgRows) {
        const rows = [];
        for (const row of orgRows) {
            if ((row.organizationTypeName || '').toLowerCase() !== 'doctor') {
                continue;
            }
            if (row.doctorCode && row.doctorClinicId) {
                rows.push({
                    doctorCode: String(row.doctorCode),
                    clinicId: String(row.doctorClinicId)
                });
            }
            if (row.doctorCode && row.accountName) {
                rows.push({
                    doctorCode: String(row.doctorCode),
                    accountName: row.accountName
                });
            }
        }
        return rows;
    }

    mapOrgRow(r) {
        const typeName = this.pick(r, ['Organization Type Name', 'Organization Type', 'Type']);
        const name = this.pick(r, ['Name']);
        const code = this.pick(r, ['Code']);
        if (!typeName && !name) {
            return null;
        }
        return {
            code: code == null ? null : String(code),
            doctorCode: this.asString(this.pick(r, ['Doctor Code'])),
            doctorClinicId: this.asString(this.pick(r, ['Doctor Clinic ID'])),
            name: name == null ? null : String(name),
            accountName: this.asString(this.pick(r, ['Account'])),
            organizationTypeName: typeName == null ? null : String(typeName),
            specialty: this.asString(this.pick(r, ['Specialty'])),
            area: this.asString(this.pick(r, ['Area'])),
            address: this.asString(this.pick(r, ['Address'])),
            customerClass: this.asString(this.pick(r, ['Class'])),
            active: this.pick(r, ['Active']),
            telephone: this.asString(this.pick(r, ['Telephone'])),
            email: this.asString(this.pick(r, ['Email']))
        };
    }

    mapDoctorRow(r) {
        const code = this.pick(r, ['Code']);
        const doctor = this.pick(r, ['Doctor']);
        if (code == null || doctor == null) {
            return null;
        }
        return {
            code: String(code),
            doctor: String(doctor),
            specialty: this.asString(this.pick(r, ['Specialty'])),
            customerClass: this.asString(this.pick(r, ['Class'])),
            isActive: this.pick(r, ['IsActive', 'Is Active']),
            mobile: this.asString(this.pick(r, ['Mobile'])),
            email: this.asString(this.pick(r, ['Email']))
        };
    }

    pick(row, keys) {
        for (const key of keys) {
            if (row[key] !== undefined && row[key] !== null && row[key] !== '') {
                return row[key];
            }
        }
        const lowerMap = {};
        Object.keys(row || {}).forEach((k) => {
            lowerMap[k.toLowerCase()] = row[k];
        });
        for (const key of keys) {
            const v = lowerMap[key.toLowerCase()];
            if (v !== undefined && v !== null && v !== '') {
                return v;
            }
        }
        return null;
    }

    asString(value) {
        if (value === null || value === undefined || value === '') {
            return null;
        }
        return String(value).trim();
    }

    mergeErrors(errors) {
        if (!errors || !errors.length) {
            return;
        }
        this.errorLines = [...this.errorLines, ...errors].slice(0, 200);
    }

    mergeDuplicates(dups) {
        if (!dups || !dups.length) {
            return;
        }
        this.duplicateHits = [...this.duplicateHits, ...dups].slice(0, 200);
    }

    async ensureSheetJs() {
        if (window.XLSX) {
            return;
        }
        await loadScript(this, SHEETJS);
    }

    readWorkbook(file) {
        return new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onload = (e) => {
                try {
                    const data = new Uint8Array(e.target.result);
                    resolve(window.XLSX.read(data, { type: 'array' }));
                } catch (err) {
                    reject(err);
                }
            };
            reader.onerror = () => reject(reader.error || new Error('File read failed'));
            reader.readAsArrayBuffer(file);
        });
    }

    downloadBlob(filename, blob) {
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = filename;
        a.click();
        URL.revokeObjectURL(url);
    }

    sleep(ms) {
        return new Promise((resolve) => setTimeout(resolve, ms));
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    reduceError(error) {
        if (!error) {
            return 'Unknown error';
        }
        if (typeof error === 'string') {
            return error;
        }
        if (error.body?.message) {
            return error.body.message;
        }
        if (Array.isArray(error.body)) {
            return error.body.map((e) => e.message).join(', ');
        }
        return error.message || JSON.stringify(error);
    }
}