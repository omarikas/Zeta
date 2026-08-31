import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import MENDIX_LOGO from '@salesforce/resourceUrl/Mendix_Logo';

export default class IntegrationsManagementConsole extends NavigationMixin(LightningElement) {
    mendixLogoUrl = MENDIX_LOGO;

    integrations = [
        {
            id: 'ims-health',
            name: 'IQVIA IMS Health',
            category: 'Market Data',
            description: 'Brick-level sell-out, market share, and geographic alignment for territory planning.',
            status: 'Connected',
            statusClass: 'status-pill status-pill--connected',
            icon: 'utility:chart',
            lastSync: 'Daily at 02:00',
            actionLabel: 'Manage Bricks',
            actionType: 'admin',
            adminComponent: 'bricksManagementConsole'
        },
        {
            id: 'onekey',
            name: 'OneKey Database',
            category: 'HCP / HCO Master',
            description: 'Validate and enrich HCP and HCO records with OneKey identifiers and affiliations.',
            status: 'Configured',
            statusClass: 'status-pill status-pill--configured',
            icon: 'utility:contact',
            lastSync: 'Weekly',
            actionLabel: null,
            actionType: null
        },
        {
            id: 'maps',
            name: 'Maps',
            category: 'Field Planning',
            description: 'OpenStreetMap routing and territory visualization in the Field Rep Planner.',
            status: 'Connected',
            statusClass: 'status-pill status-pill--connected',
            icon: 'utility:location',
            lastSync: 'Real-time',
            actionLabel: null,
            actionType: null
        },
        {
            id: 'mendix',
            name: 'Mendix',
            category: 'Low-Code Apps',
            description: 'Bi-directional sync with Mendix apps for promo budgets, project management, and cross-dept workflows.',
            status: 'Pending Setup',
            statusClass: 'status-pill status-pill--pending',
            icon: 'utility:link',
            logoUrl: MENDIX_LOGO,
            lastSync: '—',
            actionLabel: 'Open Mendix Hub',
            actionType: 'tab',
            tabApiName: 'Mendix_Integration'
        },
        {
            id: 'ibnsina-pharmaoverseas',
            name: 'Wholesaler Feeds (IbnSina / Pharmaoverseas)',
            category: 'Sell-Out Data',
            description: 'Import pharmacy withdrawal CSVs for sell-out analytics and coverage tracking.',
            status: 'Connected',
            statusClass: 'status-pill status-pill--connected',
            icon: 'utility:upload',
            lastSync: 'On demand',
            actionLabel: 'Sales Data Admin',
            actionType: 'admin',
            adminComponent: 'pharmacySalesDataAdmin'
        },
        {
            id: 'veeva-network',
            name: 'Veeva Network',
            category: 'HCP / HCO Master',
            description: 'Enterprise customer master data management and affiliation hierarchy.',
            status: 'Planned',
            statusClass: 'status-pill status-pill--planned',
            icon: 'utility:database',
            lastSync: '—',
            actionLabel: null,
            actionType: null
        },
        {
            id: 'outlook',
            name: 'Microsoft Outlook / Exchange',
            category: 'Productivity',
            description: 'Calendar sync for visit scheduling, coaching events, and field rep availability.',
            status: 'Planned',
            statusClass: 'status-pill status-pill--planned',
            icon: 'utility:event',
            lastSync: '—',
            actionLabel: null,
            actionType: null
        },
        {
            id: 'sap-erp',
            name: 'SAP / ERP',
            category: 'Finance & Supply',
            description: 'Order-to-cash, inventory, and financial reconciliation for sample and promo spend.',
            status: 'Planned',
            statusClass: 'status-pill status-pill--planned',
            icon: 'utility:money',
            lastSync: '—',
            actionLabel: null,
            actionType: null
        }
    ];

    get primaryIntegrations() {
        return this.integrations.filter((item) =>
            ['ims-health', 'onekey', 'maps', 'mendix'].includes(item.id)
        );
    }

    get additionalIntegrations() {
        return this.integrations.filter((item) =>
            !['ims-health', 'onekey', 'maps', 'mendix'].includes(item.id)
        );
    }

    handleAction(event) {
        const integrationId = event.currentTarget.dataset.integrationId;
        const integration = this.integrations.find((item) => item.id === integrationId);
        if (!integration || !integration.actionType) {
            return;
        }

        if (integration.actionType === 'tab') {
            this[NavigationMixin.Navigate]({
                type: 'standard__navItemPage',
                attributes: { apiName: integration.tabApiName }
            });
            return;
        }

        if (integration.actionType === 'admin') {
            this.dispatchEvent(
                new CustomEvent('openadminmodule', {
                    detail: {
                        componentName: integration.adminComponent,
                        title: integration.actionLabel
                    },
                    bubbles: true,
                    composed: true
                })
            );
        }
    }
}