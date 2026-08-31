import { LightningElement, api } from 'lwc';

export default class Combobox extends LightningElement {
    @api label = '';
    @api value = '';
    @api placeholder = '';
    @api options = [];
    @api disabled = false;
    @api required = false;
    @api name = '';

    get computedOptions() {
        return (this.options || []).map((o) => ({
            label: o.label,
            value: o.value,
            selected: String(o.value) === String(this.value)
        }));
    }

    handleChange(event) {
        this.value = event.target.value;
        this.dispatchEvent(new CustomEvent('change', {
            detail: { value: this.value }
        }));
    }
}
