import { LightningElement, api } from 'lwc';

export default class Button extends LightningElement {
    @api label = '';
    @api title = '';
    @api variant = 'neutral';
    @api disabled = false;
    @api iconName = '';
    @api iconPosition = 'left';

    get computedClass() {
        let cls = 'slds-button ';
        if (this.variant === 'brand') cls += 'slds-button_brand';
        else if (this.variant === 'destructive') cls += 'slds-button_destructive';
        else if (this.variant === 'success') cls += 'slds-button_success';
        else if (this.variant === 'base') cls += 'slds-button_base';
        else cls += 'slds-button_neutral';
        return cls;
    }

    handleClick(event) {
        // Native click bubbles up
    }
}
