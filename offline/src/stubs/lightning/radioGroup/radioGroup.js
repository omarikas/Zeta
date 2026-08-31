import { LightningElement, api } from 'lwc';

export default class RadioGroup extends LightningElement {
    @api label = '';
    @api name = 'radiogroup';
    @api value = '';
    @api options = [];
    @api disabled = false;

    get computedOptions() {
        return (this.options || []).map((o) => ({
            label: o.label,
            value: o.value,
            checked: String(o.value) === String(this.value)
        }));
    }

    handleChange(event) {
        this.value = event.target.value;
        this.dispatchEvent(new CustomEvent('change', {
            detail: { value: this.value }
        }));
    }
}
