import { LightningElement, api } from 'lwc';

export default class ClmAdminConsole extends LightningElement {
    @api embedded = false;

    get containerClass() {
        return this.embedded ? 'clm-admin-console clm-admin-console-embedded' : 'clm-admin-console';
    }
}