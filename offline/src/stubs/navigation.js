export const NavigationMixin = (Base) => {
    class Mixed extends Base {
        [NavigationMixin.Navigate](pageRef) {
            console.log('[NavigationMixin.Navigate]', pageRef);
            if (pageRef?.attributes?.recordId) {
                const recordId = pageRef.attributes.recordId;
                const obj = pageRef.attributes.objectApiName || 'Account';
                const sfInstance = (typeof globalThis !== 'undefined' && globalThis.PLANNER_SF_INSTANCE) || 'https://zetapharma.my.salesforce.com';
                if (obj === 'Account') {
                    window.open(`${String(sfInstance).replace(/\/$/, '')}/lightning/r/${obj}/${recordId}/view`, '_blank');
                } else {
                    // Non-Account records open in the generic standard-API record page.
                    // BASE_URL keeps it under the deploy subpath (e.g. "/Zeta/").
                    const base = (import.meta.env && import.meta.env.BASE_URL) || '/';
                    window.open(`${base}record.html?recordId=${encodeURIComponent(recordId)}&object=${encodeURIComponent(obj)}`, '_blank');
                }
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
