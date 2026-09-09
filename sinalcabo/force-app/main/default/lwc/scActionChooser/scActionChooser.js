import { LightningElement, api } from 'lwc';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';

export default class ScActionChooser extends LightningElement {
    @api options      = '';
    @api labels       = '';
    @api icons        = '';
    @api descriptions = '';
    @api colors       = '';
    @api selectedValue = '';

    // Getter puro — sem @track necessário porque depende apenas de @api props.
    // O Flow actualiza @api props reactivamente, re-renderizando o componente.
    get actions() {
        const opts  = this.options      ? this.options.split(';')      : [];
        const lbls  = this.labels       ? this.labels.split(';')       : opts;
        const icns  = this.icons        ? this.icons.split(';')        : [];
        const descs = this.descriptions ? this.descriptions.split(';') : [];
        const cols  = this.colors       ? this.colors.split(';')       : [];

        return opts.map((opt, i) => {
            const color      = (cols[i] || '#008080').trim();
            const isSelected = this.selectedValue === opt;
            return {
                value:              opt,
                label:              (lbls[i]  || opt).trim(),
                icon:               (icns[i]  || 'utility:forward').trim(),
                description:        (descs[i] || '').trim(),
                color,
                isSelected,
                cardStyle: isSelected
                    ? `border: 2px solid ${color}; background: ${color}18;`
                    : 'border: 1.5px solid #e0e0e0; background: white;',
                iconContainerStyle: `background: ${color}18; color: ${color};`
            };
        });
    }

    handleSelect(event) {
        const value = event.currentTarget.dataset.value;
        // Actualiza localmente para feedback imediato e propaga para o Flow
        this.selectedValue = value;
        this.dispatchEvent(new FlowAttributeChangeEvent('selectedValue', value));
    }
}