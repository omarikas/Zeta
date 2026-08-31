import { LightningElement, api } from 'lwc';

export default class Icon extends LightningElement {
    @api iconName = '';
    @api alternativeText = '';
    @api size = 'medium';
    @api variant = '';
    @api title = '';

    get glyph() {
        if (!this.iconName) return '';
        if (this.iconName.includes('event')) return '📅';
        if (this.iconName.includes('checkin') || this.iconName.includes('pin') || this.iconName.includes('location')) return '📍';
        if (this.iconName.includes('add')) return '＋';
        if (this.iconName.includes('close')) return '✕';
        if (this.iconName.includes('filter')) return '🔍';
        if (this.iconName.includes('refresh')) return '↻';
        if (this.iconName.includes('user')) return '👤';
        if (this.iconName.includes('account')) return '🏢';
        return '•';
    }

    get computedClass() {
        return `slds-icon_container slds-icon-${this.size}`;
    }
}
