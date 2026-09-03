import { LightningElement, api } from 'lwc';

export default class Datatable extends LightningElement {
    @api keyField = 'id';
    @api data = [];
    @api columns = [];
    @api hideCheckboxColumn = false;

    get headerColumns() {
        return this.columns || [];
    }

    get rows() {
        const cols = this.headerColumns;
        return (this.data || []).map((row) => {
            const cells = cols.map((col) => {
                const raw = row[col.fieldName];
                let className = '';
                if (col.cellAttributes && col.cellAttributes.class && col.cellAttributes.class.fieldName) {
                    className = row[col.cellAttributes.class.fieldName] || '';
                }
                return {
                    fieldName: col.fieldName,
                    label: col.label,
                    type: col.type,
                    value: raw,
                    className,
                    isUrl: col.type === 'url',
                    urlLabel:
                        col.type === 'url' && col.typeAttributes && col.typeAttributes.label
                            ? row[col.typeAttributes.label.fieldName]
                            : raw
                };
            });
            return { keyValue: row[this.keyField], cells };
        });
    }
}
