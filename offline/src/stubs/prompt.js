function escapeHtml(str) {
    if (!str) return '';
    return String(str)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#039;');
}

export default class LightningPrompt {
    static async open(options = {}) {
        const { message = '', label = 'Prompt', defaultValue = '' } = options;

        if (typeof document === 'undefined') {
            return window.prompt(message || label, defaultValue);
        }

        return new Promise((resolve) => {
            const backdrop = document.createElement('div');
            backdrop.className = 'slds-backdrop slds-backdrop_open prompt-modal-backdrop';

            const modal = document.createElement('section');
            modal.className = 'slds-modal slds-fade-in-open prompt-modal';
            modal.setAttribute('role', 'dialog');
            modal.setAttribute('tabindex', '-1');
            modal.setAttribute('aria-modal', 'true');

            modal.innerHTML = `
                <div class="slds-modal__container prompt-modal-container">
                    <header class="slds-modal__header">
                        <h2 class="slds-modal__title slds-text-heading_medium">${escapeHtml(label)}</h2>
                    </header>
                    <div class="slds-modal__content slds-p-around_medium">
                        ${message ? `<p class="prompt-modal-message">${escapeHtml(message)}</p>` : ''}
                        <div class="slds-form-element" style="margin-top: 0.75rem;">
                            <input type="text" class="slds-input prompt-input" value="${escapeHtml(defaultValue)}" />
                        </div>
                    </div>
                    <footer class="slds-modal__footer">
                        <button type="button" class="slds-button slds-button_neutral prompt-cancel-btn">Cancel</button>
                        <button type="button" class="slds-button slds-button_brand prompt-ok-btn">OK</button>
                    </footer>
                </div>
            `;

            const inputEl = modal.querySelector('.prompt-input');

            let cleanedUp = false;
            const cleanup = () => {
                if (cleanedUp) return;
                cleanedUp = true;
                if (modal.parentNode) modal.parentNode.removeChild(modal);
                if (backdrop.parentNode) backdrop.parentNode.removeChild(backdrop);
            };

            const handleConfirm = () => {
                const val = inputEl ? inputEl.value : '';
                cleanup();
                resolve(val);
            };

            const handleCancel = () => {
                cleanup();
                resolve(null);
            };

            modal.querySelector('.prompt-ok-btn')?.addEventListener('click', handleConfirm);
            modal.querySelector('.prompt-cancel-btn')?.addEventListener('click', handleCancel);
            backdrop.addEventListener('click', handleCancel);
            inputEl?.addEventListener('keydown', (e) => {
                if (e.key === 'Enter') handleConfirm();
                if (e.key === 'Escape') handleCancel();
            });

            document.body.appendChild(backdrop);
            document.body.appendChild(modal);
            setTimeout(() => inputEl?.focus(), 50);
        });
    }
}
