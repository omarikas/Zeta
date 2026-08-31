export const NavigationMixin = (Base) => {
    class Mixed extends Base {
        [NavigationMixin.Navigate](pageRef) {
            console.log('[NavigationMixin.Navigate]', pageRef);
            if (pageRef?.attributes?.recordId) {
                const sfInstance = (typeof globalThis !== 'undefined' && globalThis.PLANNER_SF_INSTANCE) || 'https://zetapharma.my.salesforce.com';
                const obj = pageRef.attributes.objectApiName || 'Account';
                window.open(`${String(sfInstance).replace(/\/$/, '')}/lightning/r/${obj}/${pageRef.attributes.recordId}/view`, '_blank');
            }
        }
        [NavigationMixin.GenerateUrl](_pageRef) {
            return Promise.resolve('#');
        }
    }
    return Mixed;
};

NavigationMixin.Navigate = Symbol('Navigate');
NavigationMixin.GenerateUrl = Symbol('GenerateUrl');
