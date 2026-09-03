import { LightningElement, api } from 'lwc';

// Minimal offline stand-in for lightning-helptext: renders an info icon whose
// tooltip text is exposed via the title attribute.
export default class Helptext extends LightningElement {
    @api content = '';
    @api iconName = 'utility:info';
    @api iconVariant = 'bare';
}
