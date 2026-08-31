function escapeHtml(str) {
    if (!str) return '';
    return String(str)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#039;');
}

export default class LightningConfirm {
    static async open(options = {}) {
        const {
            message = '',
            label = 'Confirm',
            variant = 'headerless'
        } = options;

        if (typeof document === 'undefined') {
            return window.confirm(message || label || 'Are you sure?');
        }

        return new Promise((resolve) => {
            const backdrop = document.createElement('div');
            backdrop.className = 'slds-backdrop slds-backdrop_open confirm-modal-backdrop';

            const modal = document.createElement('section');
            modal.className = 'slds-modal slds-fade-in-open confirm-modal';
            modal.setAttribute('role', 'dialog');
            modal.setAttribute('tabindex', '-1');
            modal.setAttribute('aria-modal', 'true');

            const isHeaderless = variant === 'headerless' && !label;
            const displayTitle = label || 'Confirm Action';

            modal.innerHTML = `
                <div class="slds-modal__container confirm-modal-container">
                    ${
                        !isHeaderless
                            ? `<header class="slds-modal__header">
                                  <h2 class="slds-modal__title slds-text-heading_medium">${escapeHtml(displayTitle)}</h2>
                               </header>`
                            : ''
                    }
                    <div class="slds-modal__content slds-p-around_medium">
                        <p class="confirm-modal-message">${escapeHtml(message || label)}</p>
                    </div>
                    <footer class="slds-modal__footer">
                        <button type="button" class="slds-button slds-button_neutral confirm-cancel-btn">Cancel</button>
                        <button type="button" class="slds-button slds-button_brand confirm-ok-btn">Confirm</button>
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

            const handleConfirm = () => {
                cleanup();
                resolve(true);
            };

            const handleCancel = () => {
                cleanup();
                resolve(false);
            };

            modal.querySelector('.confirm-ok-btn')?.addEventListener('click', handleConfirm);
            modal.querySelector('.confirm-cancel-btn')?.addEventListener('click', handleCancel);
            backdrop.addEventListener('click', handleCancel);

            document.body.appendChild(backdrop);
            document.body.appendChild(modal);
        });
    }
}
