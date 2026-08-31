import { LightningElement, api } from 'lwc';

export default class Textarea extends LightningElement {
    @api label = '';
    @api value = '';
    @api placeholder = '';
    @api disabled = false;
    @api required = false;

    handleInput(event) {
        this.value = event.target.value;
        this.dispatchEvent(new CustomEvent('change', {
            detail: { value: this.value }
        }));
    }

    handleChange(event) {
        this.value = event.target.value;
        this.dispatchEvent(new CustomEvent('change', {
            detail: { value: this.value }
        }));
    }
}
