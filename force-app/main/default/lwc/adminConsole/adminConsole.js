import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

const SECTION_ORDER = [
    { id: 'field', label: 'Field Management' },
    { id: 'sfe', label: 'SFE Management' },
    { id: 'platform', label: 'Platform' }
];

export default class AdminConsole extends NavigationMixin(LightningElement) {
    @track showModal = false;
    @track modalTitle = '';
    @track selectedComponent = '';
    @track searchTerm = '';

    adminCards = [
        {
            id: 'clm',
            category: 'field',
            accent: 'pink',
            title: 'CLM',
            description: 'Upload presentations, manage slides, and configure territory targeting.',
            icon: 'utility:screen',
            componentName: 'clmAdminConsole'
        },
        {
            id: 'rating-layouts',
            category: 'field',
            accent: 'orange',
            title: 'Rating Layouts',
            description: 'Design account, territory, and product rating forms with live preview.',
            icon: 'utility:rating',
            componentName: 'clmRatingLayoutEditor'
        },
        {
            id: 'coaching-management',
            category: 'field',
            accent: 'teal',
            title: 'Coaching Management',
            description: 'Browse coaching templates, create new templates, and open the template editor.',
            icon: 'utility:education',
            componentName: 'coachingTemplateManager'
        },
        {
            id: 'learning-module-management',
            category: 'field',
            accent: 'indigo',
            title: 'Learning Module Management',
            description: 'Create and manage learning materials, courses, and user assignments.',
            icon: 'utility:knowledge_base',
            componentName: 'learningModuleManager'
        },
        {
            id: 'territory-management',
            category: 'sfe',
            accent: 'indigo',
            title: 'Territory Management',
            description: 'Manage product lines, edit territories, assign users, and create demo field force accounts.',
            icon: 'utility:target',
            componentName: 'territoryManagementConsole'
        },
        {
            id: 'bricks-management',
            category: 'sfe',
            accent: 'purple',
            title: 'Bricks Management',
            description: 'Define IQVIA IMS bricks, align them to territories, and manage pharmacy account membership.',
            icon: 'utility:location',
            componentName: 'bricksManagementConsole'
        },
        {
            id: 'products-manager',
            category: 'sfe',
            accent: 'green',
            title: 'Products Manager',
            description: 'Browse the product catalog by brand and align products to territory hierarchies.',
            icon: 'utility:product',
            componentName: 'productTerritoryManager'
        },
        {
            id: 'plan-manager',
            category: 'sfe',
            accent: 'teal',
            title: 'Plan Manager',
            description: 'Manage monthly plan cycles, review employee coverage, and copy plans between months.',
            icon: 'utility:chart',
            componentName: 'planCycleManager'
        },
        {
            id: 'sales-data',
            category: 'sfe',
            accent: 'blue',
            title: 'Sales Data',
            description: 'Import IbnSina / Pharmaoverseas withdrawal CSVs and review loaded sell-out data.',
            icon: 'utility:upload',
            componentName: 'pharmacySalesDataAdmin'
        },
        {
            id: 'distributors-management',
            category: 'sfe',
            accent: 'blue',
            title: 'Distributors Management',
            description: 'Import native distributor Excel files, map products and sellout points, and load sell-out data.',
            icon: 'utility:retail_execution',
            componentName: 'distributorsManagement'
        },
        {
            id: 'account-management',
            category: 'sfe',
            accent: 'teal',
            title: 'Account Management',
            description: 'Wipe and load HCO/HCP master data, export accounts and affiliations, and review name/location duplicates.',
            icon: 'utility:people',
            componentName: 'accountManagementConsole'
        },
        {
            id: 'promo-grid',
            category: 'sfe',
            accent: 'orange',
            title: 'Promo Grid Management',
            description: 'Configure Line territory product weights, specialty focus, and class targeting.',
            icon: 'utility:table',
            componentName: 'promoGridManager'
        },
        {
            id: 'integrations-management',
            category: 'platform',
            accent: 'slate',
            title: 'Integrations Management',
            description: 'Monitor IMS Health, OneKey, Maps, Mendix, and other external platform connectors.',
            icon: 'utility:link',
            componentName: 'integrationsManagementConsole'
        },
        {
            id: 'quiz-management',
            category: 'platform',
            accent: 'orange',
            title: 'Quiz Management',
            description: 'Build and maintain quizzes and exam question banks.',
            icon: 'utility:question',
            componentName: 'quizManager'
        }
    ];

    get sectionsView() {
        const term = (this.searchTerm || '').trim().toLowerCase();
        const filtered = term
            ? this.adminCards.filter(
                  (card) =>
                      card.title.toLowerCase().includes(term) ||
                      card.description.toLowerCase().includes(term)
              )
            : this.adminCards;

        const byCategory = filtered.reduce((acc, card) => {
            if (!acc[card.category]) {
                acc[card.category] = [];
            }
            acc[card.category].push({
                ...card,
                cardClass: `admin-card admin-card--${card.accent}`,
                ariaLabel: `${card.title}. ${card.description}`
            });
            return acc;
        }, {});

        return SECTION_ORDER.filter((section) => (byCategory[section.id] || []).length > 0).map(
            (section) => {
                const cards = byCategory[section.id];
                const count = cards.length;
                return {
                    id: section.id,
                    label: section.label,
                    countLabel: `${count} ${count === 1 ? 'module' : 'modules'}`,
                    cards
                };
            }
        );
    }

    get hasResults() {
        return this.sectionsView.length > 0;
    }

    get isClmAdmin() {
        return this.selectedComponent === 'clmAdminConsole';
    }

    get isRatingLayouts() {
        return this.selectedComponent === 'clmRatingLayoutEditor';
    }

    get isCoachingManagement() {
        return this.selectedComponent === 'coachingTemplateManager';
    }

    get isTerritoryManagement() {
        return this.selectedComponent === 'territoryManagementConsole';
    }

    get isBricksManagement() {
        return this.selectedComponent === 'bricksManagementConsole';
    }

    get isProductsManager() {
        return this.selectedComponent === 'productTerritoryManager';
    }

    get isPlanManager() {
        return this.selectedComponent === 'planCycleManager';
    }

    get isSalesData() {
        return this.selectedComponent === 'pharmacySalesDataAdmin';
    }

    get isDistributorsManagement() {
        return this.selectedComponent === 'distributorsManagement';
    }

    get isAccountManagement() {
        return this.selectedComponent === 'accountManagementConsole';
    }

    get isIntegrationsManagement() {
        return this.selectedComponent === 'integrationsManagementConsole';
    }

    get isPromoGridManagement() {
        return this.selectedComponent === 'promoGridManager';
    }

    get isLearningModuleManagement() {
        return this.selectedComponent === 'learningModuleManager';
    }

    get isQuizManagement() {
        return this.selectedComponent === 'quizManager';
    }

    handleSearch(event) {
        this.searchTerm = event.target.value || '';
    }

    handleCardClick(event) {
        if (event.key && event.key !== 'Enter' && event.key !== ' ') {
            return;
        }
        if (event.key) {
            event.preventDefault();
        }
        const cardId = event.currentTarget.dataset.cardId;
        const card = this.adminCards.find((item) => item.id === cardId);
        if (!card) {
            return;
        }

        this.selectedComponent = card.componentName;
        this.modalTitle = card.title;
        this.showModal = true;
    }

    navigateToTab(apiName) {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName }
        });
    }

    closeModal() {
        this.showModal = false;
        this.selectedComponent = '';
        this.modalTitle = '';
    }

    handleOpenAdminModule(event) {
        const { componentName, title } = event.detail || {};
        if (!componentName) {
            return;
        }
        this.selectedComponent = componentName;
        this.modalTitle = title || 'Admin Module';
    }
}