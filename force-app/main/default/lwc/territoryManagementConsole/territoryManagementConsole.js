import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getTerritoryTree from '@salesforce/apex/TerritoryManagementController.getTerritoryTree';
import getProductLines from '@salesforce/apex/TerritoryManagementController.getProductLines';
import getProductsForLine from '@salesforce/apex/TerritoryManagementController.getProductsForLine';
import searchAssignableProducts from '@salesforce/apex/TerritoryManagementController.searchAssignableProducts';
import setProductLineAssignment from '@salesforce/apex/TerritoryManagementController.setProductLineAssignment';
import clearProductLineAssignment from '@salesforce/apex/TerritoryManagementController.clearProductLineAssignment';
import getParentOptions from '@salesforce/apex/TerritoryManagementController.getParentOptions';
import getAssignableUsers from '@salesforce/apex/TerritoryManagementController.getAssignableUsers';
import getManagedUsers from '@salesforce/apex/TerritoryManagementController.getManagedUsers';
import assignUserToTerritory from '@salesforce/apex/TerritoryManagementController.assignUserToTerritory';
import clearTerritoryAssignments from '@salesforce/apex/TerritoryManagementController.clearTerritoryAssignments';
import resolveAssignmentRole from '@salesforce/apex/TerritoryManagementController.resolveAssignmentRole';
import saveTerritory from '@salesforce/apex/TerritoryManagementController.saveTerritory';
import createProductLine from '@salesforce/apex/TerritoryManagementController.createProductLine';
import deleteTerritory from '@salesforce/apex/TerritoryManagementController.deleteTerritory';
import createPharmaUser from '@salesforce/apex/TerritoryManagementController.createPharmaUser';
import syncDefaultLineProductAlignments from '@salesforce/apex/TerritoryManagementController.syncDefaultLineProductAlignments';
import updateUserProfile from '@salesforce/apex/TerritoryManagementController.updateUserProfile';
import setOneTimePasswords from '@salesforce/apex/TerritoryManagementController.setOneTimePasswords';
import setUsersActive from '@salesforce/apex/TerritoryManagementController.setUsersActive';

const THERAPY_AREA_OPTIONS = [
    { label: 'Diabetes', value: 'Diabetes' },
    { label: 'CHC', value: 'CHC' },
    { label: 'Cardiovascular', value: 'Cardiovascular' },
    { label: 'Gastroenterology', value: 'Gastroenterology' }
];

const ROLE_OPTIONS = [
    { label: 'Medical Rep (mr)', value: 'mr' },
    { label: 'District Manager (dm)', value: 'dm' }
];

const LEVEL_OPTIONS = [
    { label: 'Business Unit', value: 'Business Unit' },
    { label: 'Line (Product Line)', value: 'Line' },
    { label: 'District', value: 'District' },
    { label: 'Position (Medical Rep)', value: 'Position' }
];

const PRODUCT_TYPE_FILTERS = [
    { label: 'All types', value: 'All' },
    { label: 'Brand', value: 'Brand' },
    { label: 'Detail', value: 'Detail' },
    { label: 'Sample', value: 'Sample' },
    { label: 'Brand Reminder', value: 'Brand Reminder' }
];

const ASSIGN_MODE_OPTIONS = [
    { label: 'Primary Sales Line', value: 'primary' },
    { label: 'Mirror Line', value: 'mirror' }
];

export default class TerritoryManagementConsole extends NavigationMixin(LightningElement) {
    activeTab = 'lines';

    lineRows = [];
    treeRoots = [];
    flatRows = [];
    assignUserRows = [];
    userRows = [];
    parentOptions = [];
    selectedUserIds = new Set();

    wiredTreeResult;
    wiredLinesResult;
    wiredAssignUsersResult;
    wiredManagedUsersResult;
    expandedIds = new Set();

    isSaving = false;
    showAssignModal = false;
    showTerritoryModal = false;
    showLineModal = false;
    showUserModal = false;
    showEditProfileModal = false;
    showPasswordModal = false;
    showManageProductsModal = false;

    assignTerritoryId;
    assignTerritoryName;
    selectedUserId;
    assignUserSearchTerm = '';
    userSearchTerm = '';
    includeInactiveUsers = true;
    passwordTargetIds = [];
    generatedPassword = '';

    manageLineId;
    manageLineName = '';
    lineProductRows = [];
    lineProductTypeFilter = 'All';
    lineProductSearchTerm = '';
    isLoadingLineProducts = false;
    assignProductSearchTerm = '';
    assignProductCandidates = [];
    assignProductId;
    assignMode = 'primary';
    isSearchingAssignable = false;

    draftTerritory = {
        recordId: null,
        name: '',
        externalId: '',
        parentId: null,
        level: 'District'
    };

    draftLine = {
        name: '',
        code: '',
        therapyArea: 'Diabetes'
    };

    draftUser = {
        firstName: '',
        lastName: '',
        teamCode: '',
        roleKey: 'mr',
        territoryId: null
    };

    draftProfile = {
        userId: null,
        firstName: '',
        lastName: '',
        email: '',
        username: '',
        title: '',
        department: ''
    };

    draftPassword = {
        password: '',
        confirmPassword: ''
    };

    therapyAreaOptions = THERAPY_AREA_OPTIONS;
    roleOptions = ROLE_OPTIONS;
    levelOptions = LEVEL_OPTIONS;
    productTypeFilterOptions = PRODUCT_TYPE_FILTERS;
    assignModeOptions = ASSIGN_MODE_OPTIONS;

    @wire(getProductLines)
    wiredLines(result) {
        this.wiredLinesResult = result;
        this.lineRows = (result.data || []).map((line) => {
            const typeBits = [];
            if (line.brandCount) {
                typeBits.push(`${line.brandCount} brands`);
            }
            if (line.detailCount) {
                typeBits.push(`${line.detailCount} details`);
            }
            if (line.sampleCount) {
                typeBits.push(`${line.sampleCount} samples`);
            }
            if (line.reminderCount) {
                typeBits.push(`${line.reminderCount} reminders`);
            }
            return {
                ...line,
                therapyLabel: line.therapyArea || 'No sales unit',
                typeBreakdown: typeBits.length ? typeBits.join(' · ') : 'No products linked',
                cardClass: 'line-card'
            };
        });
    }

    @wire(getTerritoryTree)
    wiredTree(result) {
        this.wiredTreeResult = result;
        if (result.data) {
            this.treeRoots = result.data;
            this.initializeExpanded();
            this.rebuildFlatRows();
        } else {
            this.treeRoots = [];
            this.flatRows = [];
        }
    }

    @wire(getAssignableUsers, { searchTerm: '$assignUserSearchTerm' })
    wiredAssignableUsers(result) {
        this.wiredAssignUsersResult = result;
        this.assignUserRows = result.data || [];
    }

    @wire(getManagedUsers, { searchTerm: '$userSearchTerm', includeInactive: '$includeInactiveUsers' })
    wiredManagedUsers(result) {
        this.wiredManagedUsersResult = result;
        const selected = this.selectedUserIds;
        this.userRows = (result.data || []).map((user) => ({
            ...user,
            selected: selected.has(user.id),
            statusLabel: user.isActive ? 'Active' : 'Inactive',
            statusClass: user.isActive ? 'badge badge-assigned' : 'badge badge-vacant',
            activateLabel: user.isActive ? 'Deactivate' : 'Activate'
        }));
    }

    @wire(getParentOptions, { childLevel: '$draftTerritory.level' })
    wiredParentOptions({ data }) {
        this.parentOptions = (data || []).map((option) => ({
            label: option.label,
            value: option.id
        }));
    }

    get hasLineRows() {
        return this.lineRows.length > 0;
    }

    get filteredLineProductRows() {
        const type = this.lineProductTypeFilter;
        const term = (this.lineProductSearchTerm || '').trim().toLowerCase();
        return (this.lineProductRows || [])
            .filter((row) => (type === 'All' ? true : row.productType === type))
            .filter((row) => {
                if (!term) {
                    return true;
                }
                return (
                    (row.name || '').toLowerCase().includes(term) ||
                    (row.productCode || '').toLowerCase().includes(term) ||
                    (row.primaryBrand || '').toLowerCase().includes(term)
                );
            })
            .map((row) => ({
                ...row,
                activeLabel: row.isActive ? 'Active' : 'Inactive',
                activeClass: row.isActive ? 'badge badge-assigned' : 'badge badge-vacant',
                linkLabel: row.matchedViaMirror ? 'Mirror' : 'Primary'
            }));
    }

    get hasFilteredLineProducts() {
        return this.filteredLineProductRows.length > 0;
    }

    get manageProductsTitle() {
        return this.manageLineName
            ? `Manage Products — ${this.manageLineName}`
            : 'Manage Products';
    }

    get assignProductOptions() {
        return (this.assignProductCandidates || []).map((product) => ({
            label: `${product.name}${product.productCode ? ` (${product.productCode})` : ''} · ${product.productType || 'Product'}`,
            value: product.id
        }));
    }

    get isAssignProductDisabled() {
        return this.isSaving || !this.assignProductId || !this.manageLineId;
    }

    get hasRows() {
        return this.flatRows.length > 0;
    }

    get hasUsers() {
        return this.userRows.length > 0;
    }

    get selectedUserCount() {
        return this.selectedUserIds.size;
    }

    get hasSelectedUsers() {
        return this.selectedUserIds.size > 0;
    }

    get isAllUsersSelected() {
        return this.userRows.length > 0 && this.userRows.every((user) => this.selectedUserIds.has(user.id));
    }

    get passwordModalTitle() {
        const count = this.passwordTargetIds.length;
        return count > 1 ? `Set One-Time Password (${count} users)` : 'Set One-Time Password';
    }

    get isAssignDisabled() {
        return this.isSaving || !this.selectedUserId;
    }

    get isTerritorySaveDisabled() {
        return this.isSaving || !this.draftTerritory.name || (!this.draftTerritory.recordId && !this.draftTerritory.externalId);
    }

    get isLineSaveDisabled() {
        return this.isSaving || !this.draftLine.name || !this.draftLine.code;
    }

    get isUserSaveDisabled() {
        return (
            this.isSaving ||
            !this.draftUser.firstName ||
            !this.draftUser.lastName ||
            !this.draftUser.teamCode ||
            !this.draftUser.roleKey
        );
    }

    get isProfileSaveDisabled() {
        return (
            this.isSaving ||
            !this.draftProfile.userId ||
            !this.draftProfile.lastName ||
            !this.draftProfile.email ||
            !this.draftProfile.username
        );
    }

    get isPasswordSaveDisabled() {
        const password = (this.draftPassword.password || '').trim();
        const confirm = (this.draftPassword.confirmPassword || '').trim();
        if (this.isSaving || this.passwordTargetIds.length === 0) {
            return true;
        }
        if (!password) {
            return false;
        }
        return password !== confirm || password.length < 8;
    }

    get territoryModalTitle() {
        return this.draftTerritory.recordId ? 'Edit Territory' : 'Add Territory';
    }

    get assignUserOptions() {
        return this.assignUserRows.map((user) => ({
            label: user.label || `${user.name} (${user.username})`,
            value: user.id
        }));
    }

    get userTerritoryOptions() {
        return this.flatRows.map((row) => ({
            label: `${row.name} (${row.level})`,
            value: row.id
        }));
    }

    handleTabChange(event) {
        this.activeTab = event.target.value;
    }

    initializeExpanded() {
        if (this.expandedIds.size > 0) {
            return;
        }
        for (const root of this.treeRoots) {
            this.expandedIds.add(root.id);
            if (root.children) {
                for (const child of root.children) {
                    this.expandedIds.add(child.id);
                }
            }
        }
        this.expandedIds = new Set(this.expandedIds);
    }

    rebuildFlatRows() {
        const rows = [];
        for (const root of this.treeRoots) {
            this.flattenNode(root, 0, rows);
        }
        this.flatRows = rows;
    }

    flattenNode(node, depth, rows) {
        const expanded = this.expandedIds.has(node.id);
        rows.push({
            key: node.id,
            id: node.id,
            name: node.name,
            externalId: node.externalId,
            level: node.level,
            depth,
            depthStyle: `padding-left: ${depth * 1.25}rem`,
            hasChildren: node.hasChildren,
            expanded,
            chevronIcon: expanded ? 'utility:chevrondown' : 'utility:chevronright',
            assignmentLabel: this.formatAssignments(node),
            isVacant: node.isVacant,
            vacantClass: node.isVacant ? 'badge badge-vacant' : 'badge badge-assigned',
            vacantLabel: node.isVacant ? 'Vacant' : 'Assigned',
            canEdit: node.canEdit,
            canDelete: node.canDelete,
            canAddChild: node.canAddChild
        });

        if (expanded && node.children) {
            for (const child of node.children) {
                this.flattenNode(child, depth + 1, rows);
            }
        }
    }

    formatAssignments(node) {
        if (!node.assignments || node.assignments.length === 0) {
            return 'Vacant';
        }
        return node.assignments
            .map((assignment) => {
                const role = assignment.role ? ` (${assignment.role})` : '';
                return `${assignment.userName}${role}`;
            })
            .join(', ');
    }

    handleToggle(event) {
        const territoryId = event.currentTarget.dataset.id;
        if (this.expandedIds.has(territoryId)) {
            this.expandedIds.delete(territoryId);
        } else {
            this.expandedIds.add(territoryId);
        }
        this.expandedIds = new Set(this.expandedIds);
        this.rebuildFlatRows();
    }

    handleAssign(event) {
        this.assignTerritoryId = event.currentTarget.dataset.id;
        this.assignTerritoryName = event.currentTarget.dataset.name;
        this.selectedUserId = null;
        this.assignUserSearchTerm = '';
        this.showAssignModal = true;
    }

    handleUserSearch(event) {
        this.userSearchTerm = event.target.value || '';
    }

    handleAssignUserSearch(event) {
        this.assignUserSearchTerm = event.target.value || '';
    }

    handleUserSelect(event) {
        this.selectedUserId = event.detail.value;
    }

    handleCloseAssign() {
        this.showAssignModal = false;
        this.assignTerritoryId = null;
        this.assignTerritoryName = null;
        this.selectedUserId = null;
    }

    async handleConfirmAssign() {
        if (!this.assignTerritoryId || !this.selectedUserId) {
            return;
        }
        this.isSaving = true;
        try {
            const role = await resolveAssignmentRole({ userId: this.selectedUserId });
            await assignUserToTerritory({
                territoryId: this.assignTerritoryId,
                userId: this.selectedUserId,
                role
            });
            this.showAssignModal = false;
            await this.refreshAll();
            this.toast('User assigned', 'Territory assignment updated.', 'success');
        } catch (error) {
            this.toast('Assign failed', this.errorMessage(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    async handleMakeVacant(event) {
        const territoryId = event.currentTarget.dataset.id;
        const territoryName = event.currentTarget.dataset.name;
        const confirmed = window.confirm(`Remove all user assignments from ${territoryName}?`);
        if (!confirmed) {
            return;
        }
        try {
            await clearTerritoryAssignments({ territoryId });
            await this.refreshAll();
            this.toast('Territory vacant', 'All assignments were removed.', 'success');
        } catch (error) {
            this.toast('Update failed', this.errorMessage(error), 'error');
        }
    }

    handleAddLine() {
        this.draftLine = { name: '', code: '', therapyArea: 'Diabetes' };
        this.showLineModal = true;
    }

    handleEditLine(event) {
        const lineId = event.currentTarget.dataset.id;
        const line = this.lineRows.find((row) => row.id === lineId);
        if (!line) {
            return;
        }
        this.draftTerritory = {
            recordId: line.id,
            name: line.name,
            externalId: line.externalId,
            parentId: null,
            level: 'Line'
        };
        this.showTerritoryModal = true;
    }

    async handleManageLineProducts(event) {
        const lineId = event.currentTarget.dataset.id;
        const line = this.lineRows.find((row) => row.id === lineId);
        if (!line) {
            return;
        }
        this.manageLineId = line.id;
        this.manageLineName = line.name;
        this.lineProductTypeFilter = 'All';
        this.lineProductSearchTerm = '';
        this.assignProductSearchTerm = '';
        this.assignProductCandidates = [];
        this.assignProductId = null;
        this.assignMode = 'primary';
        this.showManageProductsModal = true;
        await this.reloadLineProducts();
    }

    handleCloseManageProductsModal() {
        this.showManageProductsModal = false;
        this.manageLineId = null;
        this.manageLineName = '';
        this.lineProductRows = [];
        this.assignProductCandidates = [];
        this.assignProductId = null;
    }

    handleLineProductTypeFilter(event) {
        this.lineProductTypeFilter = event.detail.value;
    }

    handleLineProductSearch(event) {
        this.lineProductSearchTerm = event.target.value || '';
    }

    handleAssignProductSearch(event) {
        this.assignProductSearchTerm = event.target.value || '';
    }

    handleAssignProductSelect(event) {
        this.assignProductId = event.detail.value;
    }

    handleAssignModeChange(event) {
        this.assignMode = event.detail.value;
    }

    async reloadLineProducts() {
        if (!this.manageLineId) {
            return;
        }
        this.isLoadingLineProducts = true;
        try {
            const rows = await getProductsForLine({ lineTerritoryId: this.manageLineId });
            this.lineProductRows = rows || [];
        } catch (error) {
            this.lineProductRows = [];
            this.toast('Load failed', this.errorMessage(error), 'error');
        } finally {
            this.isLoadingLineProducts = false;
        }
    }

    async handleSearchAssignableProducts() {
        if (!this.manageLineId) {
            return;
        }
        this.isSearchingAssignable = true;
        try {
            const rows = await searchAssignableProducts({
                lineTerritoryId: this.manageLineId,
                searchTerm: this.assignProductSearchTerm
            });
            this.assignProductCandidates = rows || [];
            this.assignProductId = null;
            if (!this.assignProductCandidates.length) {
                this.toast('No products', 'No matching products available to assign.', 'info');
            }
        } catch (error) {
            this.assignProductCandidates = [];
            this.toast('Search failed', this.errorMessage(error), 'error');
        } finally {
            this.isSearchingAssignable = false;
        }
    }

    async handleAssignProductToLine() {
        if (!this.assignProductId || !this.manageLineId) {
            return;
        }
        this.isSaving = true;
        try {
            await setProductLineAssignment({
                productId: this.assignProductId,
                lineTerritoryId: this.manageLineId,
                asMirror: this.assignMode === 'mirror'
            });
            this.assignProductId = null;
            this.assignProductCandidates = [];
            await this.reloadLineProducts();
            await refreshApex(this.wiredLinesResult);
            this.toast('Product linked', 'Product was assigned to this line.', 'success');
        } catch (error) {
            this.toast('Assign failed', this.errorMessage(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    async handleRemoveProductFromLine(event) {
        const productId = event.currentTarget.dataset.id;
        const productName = event.currentTarget.dataset.name;
        if (!window.confirm(`Remove ${productName} from ${this.manageLineName}?`)) {
            return;
        }
        this.isSaving = true;
        try {
            await clearProductLineAssignment({
                productId,
                lineTerritoryId: this.manageLineId
            });
            await this.reloadLineProducts();
            await refreshApex(this.wiredLinesResult);
            this.toast('Product removed', `${productName} was unlinked from this line.`, 'success');
        } catch (error) {
            this.toast('Remove failed', this.errorMessage(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    handleAddTerritory() {
        this.draftTerritory = {
            recordId: null,
            name: '',
            externalId: '',
            parentId: null,
            level: 'District'
        };
        this.showTerritoryModal = true;
    }

    handleEditTerritory(event) {
        const row = this.flatRows.find((item) => item.id === event.currentTarget.dataset.id);
        if (!row) {
            return;
        }
        this.draftTerritory = {
            recordId: row.id,
            name: row.name,
            externalId: row.externalId,
            parentId: null,
            level: row.level
        };
        this.showTerritoryModal = true;
    }

    handleAddChildTerritory(event) {
        const row = this.flatRows.find((item) => item.id === event.currentTarget.dataset.id);
        if (!row) {
            return;
        }
        const childLevel =
            row.level === 'Head Office'
                ? 'Business Unit'
                : row.level === 'Business Unit'
                  ? 'Line'
                  : row.level === 'Line'
                    ? 'District'
                    : 'Position';
        this.draftTerritory = {
            recordId: null,
            name: '',
            externalId: '',
            parentId: row.id,
            level: childLevel
        };
        this.showTerritoryModal = true;
    }

    handleTerritoryFieldChange(event) {
        const field = event.target.dataset.field;
        this.draftTerritory = {
            ...this.draftTerritory,
            [field]: event.detail.value
        };
    }

    handleLineFieldChange(event) {
        const field = event.target.dataset.field;
        this.draftLine = {
            ...this.draftLine,
            [field]: event.detail.value
        };
    }

    handleUserFieldChange(event) {
        const field = event.target.dataset.field;
        this.draftUser = {
            ...this.draftUser,
            [field]: event.detail.value
        };
    }

    handleProfileFieldChange(event) {
        const field = event.target.dataset.field;
        this.draftProfile = {
            ...this.draftProfile,
            [field]: event.detail.value
        };
    }

    handlePasswordFieldChange(event) {
        const field = event.target.dataset.field;
        this.draftPassword = {
            ...this.draftPassword,
            [field]: event.detail.value
        };
        this.generatedPassword = '';
    }

    handleCloseTerritoryModal() {
        this.showTerritoryModal = false;
    }

    handleCloseLineModal() {
        this.showLineModal = false;
    }

    handleOpenUserModal() {
        this.draftUser = {
            firstName: '',
            lastName: '',
            teamCode: '',
            roleKey: 'mr',
            territoryId: null
        };
        this.showUserModal = true;
    }

    handleCloseUserModal() {
        this.showUserModal = false;
    }

    handleSelectAllUsers(event) {
        const checked = event.target.checked;
        if (checked) {
            this.selectedUserIds = new Set(this.userRows.map((user) => user.id));
        } else {
            this.selectedUserIds = new Set();
        }
        this.syncUserSelectionFlags();
    }

    handleToggleUserSelection(event) {
        const userId = event.currentTarget.dataset.id;
        if (event.target.checked) {
            this.selectedUserIds.add(userId);
        } else {
            this.selectedUserIds.delete(userId);
        }
        this.selectedUserIds = new Set(this.selectedUserIds);
        this.syncUserSelectionFlags();
    }

    syncUserSelectionFlags() {
        this.userRows = this.userRows.map((user) => ({
            ...user,
            selected: this.selectedUserIds.has(user.id)
        }));
    }

    handleEditProfile(event) {
        const user = this.userRows.find((row) => row.id === event.currentTarget.dataset.id);
        if (!user) {
            return;
        }
        this.draftProfile = {
            userId: user.id,
            firstName: user.firstName || '',
            lastName: user.lastName || '',
            email: user.email || '',
            username: user.username || '',
            title: user.title || '',
            department: user.businessUnit || ''
        };
        this.showEditProfileModal = true;
    }

    handleCloseEditProfileModal() {
        this.showEditProfileModal = false;
    }

    async handleSaveProfile() {
        this.isSaving = true;
        try {
            await updateUserProfile({ form: this.draftProfile });
            this.showEditProfileModal = false;
            await refreshApex(this.wiredManagedUsersResult);
            await refreshApex(this.wiredAssignUsersResult);
            this.toast('Profile updated', 'User details were saved.', 'success');
        } catch (error) {
            this.toast('Update failed', this.errorMessage(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    handleOpenPasswordForUser(event) {
        this.openPasswordModal([event.currentTarget.dataset.id]);
    }

    handleOpenPasswordForSelected() {
        if (!this.hasSelectedUsers) {
            this.toast('No users selected', 'Select one or more users first.', 'warning');
            return;
        }
        this.openPasswordModal([...this.selectedUserIds]);
    }

    openPasswordModal(userIds) {
        this.passwordTargetIds = userIds;
        this.draftPassword = { password: '', confirmPassword: '' };
        this.generatedPassword = '';
        this.showPasswordModal = true;
    }

    handleClosePasswordModal() {
        this.showPasswordModal = false;
        this.passwordTargetIds = [];
        this.generatedPassword = '';
    }

    handleGeneratePassword() {
        const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789';
        let randomPart = '';
        while (randomPart.length < 10) {
            randomPart += alphabet.charAt(Math.floor(Math.random() * alphabet.length));
        }
        const password = `Zeta!${randomPart}`;
        this.draftPassword = {
            password,
            confirmPassword: password
        };
        this.generatedPassword = password;
    }

    async handleSavePasswords() {
        const password = (this.draftPassword.password || '').trim();
        const confirm = (this.draftPassword.confirmPassword || '').trim();
        if (password && password !== confirm) {
            this.toast('Password mismatch', 'Password and confirmation must match.', 'error');
            return;
        }
        this.isSaving = true;
        try {
            const result = await setOneTimePasswords({
                userIds: this.passwordTargetIds,
                password: password || null
            });
            this.generatedPassword = result.passwordUsed;
            this.draftPassword = {
                password: result.passwordUsed,
                confirmPassword: result.passwordUsed
            };
            const summary =
                `${result.successCount} updated` + (result.failureCount ? `, ${result.failureCount} failed` : '');
            this.toast('One-time password set', summary, result.failureCount ? 'warning' : 'success');
            if (result.successCount === 0) {
                this.showPasswordModal = false;
            }
        } catch (error) {
            this.toast('Password reset failed', this.errorMessage(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    async handleToggleUserActive(event) {
        const userId = event.currentTarget.dataset.id;
        const user = this.userRows.find((row) => row.id === userId);
        if (!user) {
            return;
        }
        const nextActive = !user.isActive;
        if (!nextActive && user.isSystemAdmin) {
            this.toast('Not allowed', 'System Administrators cannot be deactivated here.', 'warning');
            return;
        }
        const verb = nextActive ? 'activate' : 'deactivate';
        if (!window.confirm(`${verb[0].toUpperCase()}${verb.slice(1)} ${user.name}?`)) {
            return;
        }
        await this.applyUserActiveStatus([userId], nextActive);
    }

    async handleBulkActivate() {
        if (!this.hasSelectedUsers) {
            this.toast('No users selected', 'Select one or more users first.', 'warning');
            return;
        }
        await this.applyUserActiveStatus([...this.selectedUserIds], true);
    }

    async handleBulkDeactivate() {
        if (!this.hasSelectedUsers) {
            this.toast('No users selected', 'Select one or more users first.', 'warning');
            return;
        }
        if (
            !window.confirm(
                `Deactivate ${this.selectedUserCount} selected user(s)? System Admins will be skipped.`
            )
        ) {
            return;
        }
        await this.applyUserActiveStatus([...this.selectedUserIds], false);
    }

    async applyUserActiveStatus(userIds, isActive) {
        this.isSaving = true;
        try {
            const result = await setUsersActive({ userIds, isActive });
            await refreshApex(this.wiredManagedUsersResult);
            await refreshApex(this.wiredAssignUsersResult);
            const summary =
                `${result.successCount} updated` +
                (result.skippedCount ? `, ${result.skippedCount} skipped` : '') +
                (result.failureCount ? `, ${result.failureCount} failed` : '');
            this.toast(
                isActive ? 'Users activated' : 'Users deactivated',
                summary,
                result.failureCount ? 'warning' : 'success'
            );
        } catch (error) {
            this.toast('Status update failed', this.errorMessage(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    handleViewUserRecord(event) {
        const userId = event.currentTarget.dataset.id;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: userId,
                objectApiName: 'User',
                actionName: 'view'
            }
        });
    }

    async handleSaveTerritory() {
        this.isSaving = true;
        try {
            await saveTerritory({ form: this.draftTerritory });
            this.showTerritoryModal = false;
            await this.refreshAll();
            this.toast('Territory saved', 'Territory details were updated.', 'success');
        } catch (error) {
            this.toast('Save failed', this.errorMessage(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    async handleSaveLine() {
        this.isSaving = true;
        try {
            await createProductLine({
                name: this.draftLine.name,
                code: this.draftLine.code,
                therapyArea: this.draftLine.therapyArea
            });
            if (this.draftLine.therapyArea) {
                await syncDefaultLineProductAlignments();
            }
            this.showLineModal = false;
            await this.refreshAll();
            this.toast('Line created', 'Product line and default district/MR territories were created.', 'success');
        } catch (error) {
            this.toast('Create failed', this.errorMessage(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    async handleSaveUser() {
        this.isSaving = true;
        try {
            const result = await createPharmaUser({
                firstName: this.draftUser.firstName,
                lastName: this.draftUser.lastName,
                teamCode: this.draftUser.teamCode,
                roleKey: this.draftUser.roleKey,
                territoryId: this.draftUser.territoryId,
                roleInTerritory: null
            });
            this.showUserModal = false;
            await refreshApex(this.wiredManagedUsersResult);
            await refreshApex(this.wiredAssignUsersResult);
            await refreshApex(this.wiredTreeResult);
            this.toast('User created', result.message, 'success');
        } catch (error) {
            this.toast('Create failed', this.errorMessage(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    async handleDeleteTerritory(event) {
        const territoryId = event.currentTarget.dataset.id;
        const territoryName = event.currentTarget.dataset.name;
        const confirmed = window.confirm(`Delete territory ${territoryName}? This cannot be undone.`);
        if (!confirmed) {
            return;
        }
        try {
            await deleteTerritory({ territoryId });
            await this.refreshAll();
            this.toast('Territory deleted', `${territoryName} was removed.`, 'success');
        } catch (error) {
            this.toast('Delete failed', this.errorMessage(error), 'error');
        }
    }

    async refreshAll() {
        await refreshApex(this.wiredTreeResult);
        await refreshApex(this.wiredLinesResult);
        await refreshApex(this.wiredAssignUsersResult);
        await refreshApex(this.wiredManagedUsersResult);
        this.rebuildFlatRows();
    }

    errorMessage(error) {
        return error?.body?.message || error?.message || 'Unexpected error';
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}