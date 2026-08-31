export class ShowToastEvent extends CustomEvent {
    constructor(detail = {}) {
        const payload = {
            title: detail.title || '',
            message: detail.message || '',
            variant: detail.variant || 'info',
            mode: detail.mode || 'dismissible',
            messageData: detail.messageData
        };
        super('lightning__showtoast', {
            bubbles: true,
            composed: true,
            detail: payload
        });
        console.log('[Toast]', payload.title, payload.message, payload.variant);

        if (typeof window !== 'undefined') {
            setTimeout(() => {
                window.dispatchEvent(
                    new CustomEvent('lightning__showtoast', {
                        bubbles: true,
                        composed: true,
                        detail: payload
                    })
                );
            }, 0);
        }
    }
}
