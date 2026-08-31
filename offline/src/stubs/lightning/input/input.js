import { LightningElement, api } from 'lwc';

export default class Input extends LightningElement {
    @api label = '';
    @api type = 'text';
    @api value = '';
    @api placeholder = '';
    @api disabled = false;
    @api required = false;
    @api min;
    @api max;
    @api step;

    get actualType() {
        if (this.type === 'datetime' || this.type === 'datetime-local') {
            return 'datetime-local';
        }
        return this.type || 'text';
    }

    handleInput(event) {
        this.value = event.target.value;
        this.dispatchEvent(
            new CustomEvent('change', {
                detail: { value: this.value }
            })
        );
    }

    handleChange(event) {
        this.value = event.target.value;
        this.dispatchEvent(
            new CustomEvent('change', {
                detail: { value: this.value }
            })
        );
    }
}
