import { LightningElement, api } from 'lwc';

export default class Spinner extends LightningElement {
    @api alternativeText = 'Loading';
    @api size = 'medium';
    @api variant = 'base';

    get computedClass() {
        return `slds-spinner slds-spinner_${this.size}`;
    }
}
