import { LightningElement, api } from 'lwc';

export default class ButtonIcon extends LightningElement {
    @api iconName = '';
    @api alternativeText = '';
    @api title = '';
    @api variant = 'border';
    @api size = 'medium';
    @api disabled = false;

    get glyph() {
        if (!this.iconName) return '•';
        if (this.iconName.includes('left')) return '◀';
        if (this.iconName.includes('right')) return '▶';
        if (this.iconName.includes('close')) return '✕';
        if (this.iconName.includes('add')) return '+';
        if (this.iconName.includes('edit')) return '✎';
        return '•';
    }

    get computedClass() {
        return 'slds-button slds-button_icon slds-button_icon-border';
    }
}
