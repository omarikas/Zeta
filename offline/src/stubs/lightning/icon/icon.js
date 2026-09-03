import { LightningElement, api } from 'lwc';

export default class Icon extends LightningElement {
    @api iconName = '';
    @api alternativeText = '';
    @api size = 'medium';
    @api variant = '';
    @api title = '';

    get glyph() {
        if (!this.iconName) return '';
        if (this.iconName.includes('add')) return '＋';
        if (this.iconName.includes('close')) return '✕';
        if (this.iconName.includes('refresh')) return '↻';
        return '•';
    }

    get computedClass() {
        return `slds-icon_container slds-icon-${this.size}`;
    }
}
