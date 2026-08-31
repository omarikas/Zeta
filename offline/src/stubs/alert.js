function escapeHtml(str) {
    if (!str) return '';
    return String(str)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#039;');
}

export default class LightningAlert {
    static async open(options = {}) {
        const { message = '', label = 'Alert' } = options;

        if (typeof document === 'undefined') {
            window.alert(message || label);
            return;
        }

        return new Promise((resolve) => {
            const backdrop = document.createElement('div');
            backdrop.className = 'slds-backdrop slds-backdrop_open alert-modal-backdrop';

            const modal = document.createElement('section');
            modal.className = 'slds-modal slds-fade-in-open alert-modal';
            modal.setAttribute('role', 'dialog');
            modal.setAttribute('tabindex', '-1');
            modal.setAttribute('aria-modal', 'true');

            modal.innerHTML = `
                <div class="slds-modal__container alert-modal-container">
                    <header class="slds-modal__header">
                        <h2 class="slds-modal__title slds-text-heading_medium">${escapeHtml(label)}</h2>
                    </header>
                    <div class="slds-modal__content slds-p-around_medium">
                        <p class="alert-modal-message">${escapeHtml(message)}</p>
                    </div>
                    <footer class="slds-modal__footer">
                        <button type="button" class="slds-button slds-button_brand alert-ok-btn">OK</button>
                    </footer>
                </div>
            `;

            let cleanedUp = false;
            const cleanup = () => {
                if (cleanedUp) return;
                cleanedUp = true;
                if (modal.parentNode) modal.parentNode.removeChild(modal);
                if (backdrop.parentNode) backdrop.parentNode.removeChild(backdrop);
            };

            const handleClose = () => {
                cleanup();
                resolve();
            };

            modal.querySelector('.alert-ok-btn')?.addEventListener('click', handleClose);
            backdrop.addEventListener('click', handleClose);

            document.body.appendChild(backdrop);
            document.body.appendChild(modal);
        });
    }
}
